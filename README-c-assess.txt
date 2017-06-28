                             c-assess-test-1.1.4
                               James A. Kupsch
                                  2016-10-23

This document describes the files that need to be placed in the virtual
machine's input directory to perform a build, or build and assessment of
a C/C++ package:

From this release, the files included in the in-files directory need to
be placed in the VM's input directory, and the file
swamp-conf/sys-os-dependencies.conf needs to be combined with the other
os-dependencies files to create the os-dependencies.conf file (see below).
The important files in this release are as follows:

    in-files/
      build_assess_driver
      buildbug
      no_build_helper
      run.sh
    swamp-conf/
      sys-os-dependencies.conf

In addition, the following files needs to be placed in the input directory:

    - run-params.conf
        Contains KEY=VALUE lines using Bash syntax (no spaces around equal
        sign and special characters need to quoted) where key is
            SWAMP_USERNAME                                  required
                username used to build, assess or parse
            SWAMP_USERID                                    required
                uid of username
            SWAMP_PASSWORD                                  optional
                password of username
            SWAMP_PASSWORD_IS_ENCRYPTED                     optional
                if set, SWAMP_PASSWORD is hash to use directly
            SLEEP_TIME                                      optional
                amount of time to sleep (to wait for network)
            NORUNPAYLOAD                                    optional
                if set to a non-empty value, the payload will
                not be run, and the VM will not shutdown
            NOSHUTDOWN                                      optional
                if set to a non-empty value, the VM will not
                shutdown after the payload is run
            USER_CONF                                       optional
                name of a gzipped tar file that is unarcharived as the user
                in the user's home directory
            ROOT_PAYLOAD                                    optional
                path to a Bash script file, that is executed as root in the
                VM.  The file is sourced by run.sh and inherits the variables
                and environment of run.sh
            USER_PAYLOAD                                    optional
                path to an executable file, that is executed as the user in the
                VM instead of build_assess_driver.  This execuatble is passed three
                parameters:  the input directory path, the output directory
                path, and the path to a file containing the environment
                variables of run.sh.  This script is responsible for loading
                the os dependencies as is done in build_assess_driver.

    - run.conf
	Must contains the option 'goal'.  It may also optionally contain the
	option 'internet-inaccessible'.  The 'goal' option is of the following
	form:
            goal=<GOAL_TYPE>

        where <GOAL_TYPE> can have the following values:
            none
            build
            assess
                not supported for C/C++
            parse
            build+assess
            assess+parse
                not supported for C/C++
            build+assess+parse

	The 'internet-inaccessible' is a boolean value.  The value must be
	'true' or 'false'.  If absent it has the value false.  If the value is
	'true', the framework will not attempt to use the internet.  It does not
	prevent packages from using the internet durning their configuration or
	build.

    - os-dependencies.conf
        Contains KEY=VALUE lines where the key contains the platform name,
        and the value is a space separated list of strings that name valid
        packages using the native package manager on the platform such as
            dependencies-<PLAT_NAME>=os-pkg1 os-pkg2 ...

        This file must contain the combined OS dependencies required by:
          this software        - sys-os-dependencies.conf (in swamp-conf dir)
          the package          - pkg-os-dependencies.conf
          the assessment tool  - tool-os-dependencies.conf
          the parser           - parser-os-dependencies.conf

    - package.conf
    - <package-archive>
        Present for goals containing 'build'.  The package.conf describes the
        package and how it is built.  It is a key/value based file and has the
        following valid keys:
            package-short-name
            package-version
            package-archive
            package-archive-md5
            package-archive-sha512
            build-sys
            package-dir
            config-dir
            config-cmd
            config-opt
            build-dir
            build-file
            build-cmd
            build-opt
            build-target

    - build.conf
    - <build-archive>
        Present for goals containing 'parse' without a goal of 'build'.
        The build.conf describes the result of the build.  It is a key/value
        based file and has the following valid keys:
            build-summary-file
            build-dir
            build-archive
            no-build-failures

    - tool.conf
    - <tool-archive>
        Present for goals containing 'assess'.  The tool.conf describes the
        tool and how to run it.  It is a key/value based file and has the
        following valid keys:
            tool-short-name
            tool-version
            tool-archive
            tool-archive-md5
            tool-archive-sha512
            tool-dir
            tool-cmd
            tool-uuid
            tool-type

    - results.conf
    - <results-archive>
        Present for goals containing 'parse' without 'assess'.  The
        results.conf describes the results and is generated by an assessment.
        It is a key/value based file and has the following valid keys:
            assessment-summary-file
            results-archive
            results-archive-md5
            results-archive-sha512
            results-dir
            results-uuid

    - resultparser.conf
    - <resultparser-archive>
        Present for goals containing 'parse'.  The resultparser.conf describes
        the parsed results and is generated by an assessment.  It is a
        key/value based file and has the following valid keys:
            result-parser-archive
            result-parser-archive-md5
            result-parser-archive-sha512
            result-parser-dir
            result-parser-cmd
            result-parser-uuid
    
    - services.conf
	Present for goals containing 'parse' and the tool being Parasoft's
	C/C++test (ps-ctest).  The same file can be used with java-assess and
	Parasoft's Jtest (ps-jtest).  It is a key/value based file and has the
	following valid keys:
	    tool-ps-ctest-license-host
	    tool-ps-ctest-license-port
	    tool-ps-jtest-license-host
	    tool-ps-jtest-license-port
	    tool-gt-csonar-license-host
	    tool-gt-csonar-license-port
	    tool-rl-goanna-license-host
	    tool-rl-goanna-license-port
