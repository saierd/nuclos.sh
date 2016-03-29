A command line script for installing and managing [Nuclos](http://www.nuclos.de/) servers.

# Installation

Just download the script `nuclos.sh` so that it is executable. Run it with the `-h` flag to get an overview over the commands that are available.

You might want to use the following command to easily do that on a server.

    $ wget https://raw.githubusercontent.com/saierd/nuclos.sh/master/nuclos.sh

# Configuration

By default, the script will connect to Nuclos on the machine that you run the script on. It will use the default user `nuclos` with no password.

You can change this in a few ways. There are command line flags for setting the URL to the Nuclos server and the username. See the scripts usage information for the details.

You can also use a configuration file to specify things. Take a look at the [example file](https://github.com/saierd/nuclos.sh/blob/master/nuclosrc.example) to see the possible variables and their default values.

The script tries to read the following configuration files (in this order, files which do not exist are simply skipped):
* `~/.nuclosrc`
* `.nuclosrc`
* `nuclosrc`

You do not have to specify all the variables in all of the files and you can override values in configuration files that are read later (or by specifying command line options).

You also do not have to specify your password anywhere. The script will automatically ask for the password if it needs to.

# Installing a Nuclos server

By default, the installation does not set up a PostgreSQL server in case you want to use your own one. If you do want to install PostgreSQL on the same machine as Nuclos (the same way the Nuclos installer does it), you can run the following command.

    $ ./nuclos.sh install postgres

You can set up the Nuclos server itself by giving the version you want to install to the `install` command.

    $ ./nuclos.sh install 4.7.2

This will first install all the necessary dependencies for Nuclos (mainly Java). Then it will download the Nuclos installer and run it with the default settings.

The script downloads Nuclos from `ftp.nuclos.de` which unfortunately needs a password. I wasn't able to get access without a password and I do not want to publish their password in this repository. That's why you will have to find it out yourself (Google might help) and give it to the script. This can either be done by putting it into the script itself (the variables are listed at the top) or by specifying the variable `nuclos_ftp_password` in a configuration file.

There are some possibilities to customize the installation:

* You can provide the connection information to your existing PostgreSQL server by specifying it in a configuration file.
* You can also specify a complete Nuclos configuration file with the `-c` flag.

# Managing a Nuclos server

There are `start`, `stop` and `restart` commands which do exactly what their name says. These commands only work if you are on the same machine as the Nuclos server.

    $ ./nuclos.sh start

The `status` command checks whether the server is running.

There are also commands for starting the maintenance mode.

    $ ./nuclos.sh maintenance
    $ ./nuclos.sh maintenance end

# Managing Nuclets

To import a Nuclet, run the `import` command and give it the filename of you Nuclet.

    $ ./nuclos.sh import test.nuclet

To export a Nuclet, you have to specify its name and the filename it should be written into.

    $ ./nuclos.sh export test test.nuclet

----

Published under the terms of the [MIT license](https://github.com/saierd/nuclos.sh/blob/master/LICENSE).
