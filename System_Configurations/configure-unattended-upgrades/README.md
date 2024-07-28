# Configure Unattended Upgrades Script

Unattended Upgrades is a package in Debian and Ubuntu systems that allows for automatic installation of security updates, ensuring that your system remains secure and up-to-date without requiring manual intervention.

This script configures unattended-upgrades on a Debian-based system to automatically download and install updates. \
You can customize various settings such as email notifications, reboot behavior, and the specific time for automatic reboots.

## Benefits of Unattended Upgrades

1. **Enhanced Security**: Automatically applying security updates helps protect your system from vulnerabilities and exploits.
2. **Convenience**: Saves time and effort by automating the update process, eliminating the need for manual intervention.
3. **Consistency**: Ensures that all systems receive updates uniformly, reducing the risk of some systems being left unpatched.
4. **Reliability**: Reduces the chance of human error in the update process, leading to a more reliable and secure system environment.

By using unattended-upgrades, you can maintain the security and stability of your systems with minimal effort, ensuring that they remain protected against the latest threats and vulnerabilities.

## Usage

To use this script, follow the steps below:

1. **Save the script** to a file, for example, `configure-unattended-upgrades.sh`.
2. **Make the script executable**:
   ```bash
   chmod +x configure-unattended-upgrades.sh
   ```
3. **Run the script** with the desired parameters. For example:
   ```bash
   ./configure-unattended-upgrades.sh --enable enable --email info@mailbase.info --reboot false --reboot-if-required true --reboot-time "03:11"
   ```

## Parameters

- `--enable <enable|disable>`: Enable or disable unattended-upgrades (`enable` or `disable`). Default is `enable`.
- `--email <email>`: Email address to receive notifications. Default is none.
- `--reboot <true|false>`: Enable or disable automatic reboot. Default is `false`.
- `--reboot-if-required <true|false>`: Enable or disable automatic reboot only if required. Default is `false`.
- `--reboot-time <HH:MM>`: Time to perform the reboot (format: HH:MM). Default is none.

## Example

To enable unattended-upgrades with email notifications to `info@mailbase.info`, disable automatic reboots, but enable automatic reboots if required, and set the reboot time to `03:11`, use the following command:

```bash
./configure-unattended-upgrades.sh --enable enable --email info@mailbase.info --reboot false --reboot-if-required true --reboot-time "03:11"
```
