{ self, pkgs }:

pkgs.nixosTest {
  name = "mqtt2timescale-test";

  nodes.machine =
    { config, pkgs, ... }:
    {

      imports = [
        self.nixosModules.mqtt2timescale
      ];

      system.stateVersion = "25.05";

      services = {

        mqtt2timescale.enable = true;

        mosquitto = {
          enable = true;
          listeners = [
            {
              users = {
                "zigbee" = {
                  acl = [ "readwrite #" ];
                  password = "test";
                };
              };
            }
          ];
        };
        postgresql = {
          enable = true;
          enableTCPIP = true;
          extensions = with pkgs.postgresqlPackages; [
            config.services.postgresql.package.pkgs.timescaledb
          ];
          settings = {
            timezone = "Europe/Berlin";
            shared_preload_libraries = "timescaledb";
            log_connections = true;
          };
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("mosquitto.service")
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_unit("mqtt2timescale.service")
  '';
}
