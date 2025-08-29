CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE sensor (
sensor_id SERIAL PRIMARY KEY,
sensor_name TEXT NOT NULL UNIQUE,
description TEXT NULL
);

CREATE TABLE last_seen (
sensor_id INT PRIMARY KEY,
last_seen TIMESTAMPTZ NOT NULL,
modified TIMESTAMPTZ NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);

CREATE TABLE temperature (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value DOUBLE PRECISION NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('temperature', 'time');

CREATE TABLE humidity (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value DOUBLE PRECISION NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('humidity', 'time');

CREATE TABLE pressure (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value DOUBLE PRECISION NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('pressure', 'time');

CREATE TABLE battery (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value DOUBLE PRECISION NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('battery', 'time');

CREATE TABLE illuminance (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value INT NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('illuminance', 'time');

CREATE TABLE occupancy (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value BOOL NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('occupancy', 'time');

CREATE TABLE leakage (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value BOOL NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('leakage', 'time');

CREATE TABLE voltage (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value INT NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('voltage', 'time');

CREATE TABLE battery_low (
time TIMESTAMPTZ NOT NULL,
sensor_id INT,
value BOOL NOT NULL,
CONSTRAINT fk_sensor_id FOREIGN KEY(sensor_id) REFERENCES sensor(sensor_id)
);
SELECT create_hypertable('battery_low', 'time');
