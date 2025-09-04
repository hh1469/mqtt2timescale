use core::str;
use std::{
    io::BufRead,
    str::FromStr,
    sync::mpsc::{self, Receiver, Sender},
    thread::{self, JoinHandle},
    time::SystemTime,
};

use anyhow::anyhow;
use chrono::{DateTime, Utc};
use clap::Parser;
use postgres::Transaction;
use rumqttc::{Client, ConnAck, ConnectReturnCode, Event, MqttOptions, Packet, Publish};
use serde::Deserialize;
#[derive(Debug, Clone)]
struct MqttCredentials {
    username: String,
    password: String,
}

refinery::embed_migrations!("migrations");

impl FromStr for MqttCredentials {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let (username, password) = s.split_once(':').ok_or_else(|| {
            "credentials must be passed in format 'username:password'".to_string()
        })?;
        Ok(MqttCredentials {
            username: username.to_string(),
            password: password.to_string(),
        })
    }
}

#[derive(Debug, Parser)]
struct Cli {
    #[arg(env = "MQTT2TIMESCALE_DATABASE")]
    database: String,
    #[arg(env = "MQTT2TIMESCALE_MQTT_ID")]
    mqtt_id: String,
    #[arg(env = "MQTT2TIMESCALE_MQTT_HOST")]
    mqtt_host: String,
    #[arg(default_value_t = 1883, env = "MQTT2TIMESCALE_MQTT_PORT")]
    mqtt_port: u16,
    #[arg(env = "MQTT2TIMESCALE_MQTT_CREDENTIALS")]
    mqtt_credentials: Option<MqttCredentials>,
    #[arg(short, long)]
    sensor_names: Option<String>,
}

#[derive(Debug)]
struct Message {
    topic: String,
    payload: bytes::Bytes,
}

#[derive(Debug, Deserialize)]
struct Payload {
    battery_low: Option<bool>,
    battery: Option<f64>,
    humidity: Option<f64>,
    illuminance: Option<i32>,
    last_seen: Option<String>,
    occupancy: Option<bool>,
    pressure: Option<f64>,
    temperature: Option<f64>,
    voltage: Option<i32>,
    water_leak: Option<bool>,
}

fn insert_sensor_names(filename: &str, pg: &mut postgres::Client) -> anyhow::Result<()> {
    let f = std::fs::File::open(filename)?;
    let reader = std::io::BufReader::new(f);

    for line in reader.lines() {
        let line = line?;
        pg.execute(
            "INSERT INTO SENSOR (sensor_name) values ($1) ON CONFLICT DO NOTHING",
            &[&line],
        )?;
    }
    Ok(())
}

fn make_timestamp(time: &str) -> anyhow::Result<SystemTime> {
    Ok(DateTime::parse_from_rfc3339(time)?
        .with_timezone(&Utc)
        .into())
}

fn insert<T>(
    t: &mut Transaction,
    table: &str,
    timestamp: &SystemTime,
    sensor_id: i32,
    value: T,
) -> anyhow::Result<u64>
where
    T: std::marker::Sync + postgres::types::ToSql,
{
    let query = format!(
        "INSERT INTO {} (time, sensor_id, value) values ($1, $2, $3)",
        table
    );

    Ok(t.execute(&query, &[&timestamp, &sensor_id, &value])?)
}

fn insert_last_seen(
    t: &mut Transaction,
    sensor_id: i32,
    last_seen: &SystemTime,
    modified: &SystemTime,
) -> anyhow::Result<u64> {
    let rc = t.execute(
        r#"INSERT INTO last_seen (sensor_id, last_seen, modified) values ($1, $2, $3)
        ON CONFLICT (sensor_id)
        DO UPDATE SET last_seen = $2, modified = $3"#,
        &[&sensor_id, &last_seen, &modified],
    )?;

    Ok(rc)
}

fn handle_message(mut t: Transaction, data: Message) -> anyhow::Result<()> {
    let rc = t.query(
        "SELECT sensor_id from sensor WHERE sensor_name = $1",
        &[&data.topic],
    )?;

    let sensor_id = match rc.first() {
        Some(row) => match row.try_get::<_, i32>(0) {
            Ok(id) => id,
            Err(e) => {
                log::error!("{}", e);
                anyhow::bail!(e);
            }
        },
        None => return Ok(()),
    };

    log::info!("{:?}", data);

    let payload = match String::from_utf8(data.payload.to_vec()) {
        Ok(s) => match serde_json::from_str::<Payload>(&s) {
            Ok(payload) => payload,
            Err(e) => {
                log::error!("{}", e);
                // continue;
                anyhow::bail!(e);
            }
        },
        Err(e) => {
            log::error!("{}", e);
            // continue;
            anyhow::bail!(e);
        }
    };

    let last_seen = match payload.last_seen {
        Some(time) => make_timestamp(&time)?,
        None => {
            log::warn!("no times");
            // continue;
            return Ok(());
        }
    };

    let now = SystemTime::now();

    match SystemTime::now().duration_since(last_seen) {
        Ok(duration) => {
            if duration.as_millis() > 1000 {
                log::error!("check time value: {}", duration.as_millis());
            }
        }
        Err(e) => log::warn!("{}", e),
    }

    insert_last_seen(&mut t, sensor_id, &last_seen, &now)?;

    if let Some(temperature) = payload.temperature {
        insert(&mut t, "temperature", &now, sensor_id, temperature)?;
    }

    if let Some(humidity) = payload.humidity {
        insert(&mut t, "humidity", &now, sensor_id, humidity)?;
    }

    if let Some(battery) = payload.battery {
        insert(&mut t, "battery", &now, sensor_id, battery)?;
    }

    if let Some(pressure) = payload.pressure {
        insert(&mut t, "pressure", &now, sensor_id, pressure)?;
    }

    if let Some(occupancy) = payload.occupancy {
        insert(&mut t, "occupancy", &now, sensor_id, occupancy)?;
    }

    if let Some(illuminance) = payload.illuminance {
        insert(&mut t, "illuminance", &now, sensor_id, illuminance)?;
    }

    if let Some(battery_low) = payload.battery_low {
        insert(&mut t, "battery_low", &now, sensor_id, battery_low)?;
    }

    if let Some(voltage) = payload.voltage {
        insert(&mut t, "voltage", &now, sensor_id, voltage)?;
    }

    if let Some(water_leak) = payload.water_leak {
        insert(&mut t, "water_leak", &now, sensor_id, water_leak)?;
    }

    t.commit()?;

    Ok(())
}

fn main() -> Result<(), anyhow::Error> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let cli = Cli::parse();

    // database migration
    let mut postgres = postgres::Client::connect(&cli.database, postgres::NoTls)?;
    migrations::runner().run(&mut postgres)?;

    if let Some(s) = cli.sensor_names {
        return Ok(insert_sensor_names(&s, &mut postgres)?);
    }

    // connect to mqtt
    let mut options = MqttOptions::new(cli.mqtt_id, cli.mqtt_host, cli.mqtt_port);
    options.set_keep_alive(std::time::Duration::from_secs(5));
    options.set_max_packet_size(1024 * 1024, 1024 * 1024);

    if let Some(credentials) = cli.mqtt_credentials {
        options.set_credentials(credentials.username, credentials.password);
    }

    let (client, mut connection) = Client::new(options, 10);
    client.subscribe("#", rumqttc::QoS::AtMostOnce)?;

    let (tx, rx): (Sender<Message>, Receiver<Message>) = mpsc::channel();

    let sender: JoinHandle<anyhow::Result<()>> = thread::spawn(move || {
        for notification in connection.iter() {
            match notification {
                Ok(Event::Incoming(Packet::ConnAck(ConnAck {
                    code: ConnectReturnCode::Success,
                    ..
                }))) => {
                    log::info!("connected");
                }
                Ok(Event::Incoming(Packet::Publish(Publish { topic, payload, .. }))) => {
                    match tx.send(Message { topic, payload }) {
                        Ok(_) => continue,
                        Err(e) => anyhow::bail!(e),
                    }
                }
                Ok(Event::Incoming(_)) => {}
                Ok(Event::Outgoing(_)) => {}
                Err(e) => {
                    log::error!("{}", e);
                    anyhow::bail!(e);
                }
            }
        }

        Ok(())
    });

    let receiver: JoinHandle<anyhow::Result<()>> = thread::spawn(move || loop {
        let data = rx.recv()?;

        let t = postgres.transaction()?;

        if let Err(e) = handle_message(t, data) {
            log::error!("{}", e);
            return Err(anyhow!("das war nix"));
        }
    });

    match sender.join() {
        Ok(r) => {
            if let Err(e) = r {
                log::error!("{}", e);
            }
        }
        Err(e) => log::error!("{:?}", e),
    }

    match receiver.join() {
        Ok(r) => {
            if let Err(e) = r {
                log::error!("{}", e);
            }
        }
        Err(e) => log::error!("{:?}", e),
    }

    Ok(())
}
