# Apache Virtual Host Generator

This is a simple Bash script to automatically generate Apache virtual host configurations for your projects. It generates separate configurations for the frontend and backend based on the user input.

## Pre-requisites

The script needs to be run on a system with Apache installed and with root privileges as it writes the configuration files to `/etc/apache2/sites-available/`.

## Usage

1. Download the script file `generate_vhosts.sh` to your local machine.

2. Make the script executable with the following command:

```bash
chmod +x generate_vhosts.sh
```

3. Run the script with root privileges:

```bash
sudo ./generate_vhosts.sh
```

4. Follow the interactive prompts. You will be asked whether you want to generate configurations for the frontend, backend, or both. You will then be asked to provide the domain name and the document root path for the configurations you have chosen to generate.

5. After successfully running the script, the configurations will be saved in `/etc/apache2/sites-available/` with the domain name as the file name and `.conf` extension.

## Important Note

Don't forget to enable the newly created sites using `a2ensite` and reload or restart the Apache service for the changes to take effect.

## Support

If you encounter any issues or need further assistance, please open an issue in this repository.

## License

This project is licensed under the MIT License - see the `LICENSE` file for details.
