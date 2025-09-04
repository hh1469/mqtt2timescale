CREATE TABLE water_leak (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value BOOL NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('water_leak', 'time');
