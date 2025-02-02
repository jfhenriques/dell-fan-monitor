# Instructions

1. Clone and build https://github.com/jfhenriques/dellfan into `/opt/delfan`
   
   Also, clone the current repo https://github.com/jfhenriques/dell-fan-monitor, into opt `/opt/dell-fan-monitor`

2. Copy `example.dell-fan-monitor.conf` to `/etc/dell-fan-monitor.conf` and modify or leave defaults

   Alternatively modify `dell-fan-monitor.service` and add the new file location at the end of ExecStart

   example:
    ```
    ExecStart=/opt/dell-fan-monitor/dell-fan-monitor.sh /new/path/speeds.conf
    ```
    
3. Copy `example.dell-fan-monitor.service` to `/etc/systemd/system/dell-fan-monitor.service`

4. `systemctl daemon-reload`

5. `systemctl enable --now dell-fan-monitor.service`