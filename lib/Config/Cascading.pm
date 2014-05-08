package Config::Cascading;

use 5.006001;
use strict;
use warnings;

our $VERSION = '0.001';

sub import {
    my $cl = shift;  my $pkg = caller;  my %v = (@_, @_ % 2 ? undef : ());
    no strict 'refs';
    for (keys %v) {
        /^\$([^\W\d]\w*)$/x ? ${"${pkg}::${1}"} = $cl->load($v{$_}) : die "Cannot import config into $_"
    }
    return;
}

sub _load_section {
    my ($class, $name, $config) = @_;
    my $pkg = ref($class) || $class;
    return eval { $class->$name($config); 1 } || die "Failed to execute ${pkg}->$name: $@\n"
      if $class->can($name);
    (my $f = "$pkg.pm") =~ s|::|/|g;
    my $full = $INC{$f} || die "Could not find \$INC{$f}";
    $full =~ s|\.pm$|/${name}.pm| or die "Could not find full name for $name from $full";
    return 0 if ($name eq 'override' || !$class->force_section($name)) && ! -e $full;
    return eval {
        require $full;
        "${pkg}::$name"->initialize($config);
        1;
    } || die "Failed to load ${pkg}::$name: $@\n";
}

sub force_section {}

sub load_order { return [qw(server_type)] }

sub initialize {}

sub finalize {}

sub load {
    my ($class, $over, $config_ref) = @_;

    my @order  = @{ $class->load_order };
    my $config = ($config_ref && ref($config_ref) eq 'HASH') ? $config_ref : {};
    $class->_load_section('override', $config);
    @order =
      grep { $_ }
      map  {   ($over && $over->{$_})
            ||  $config->{$_}
            || (   ( $class eq 'Config::Default' || eval { require Config::Default } )
                && ( $Config::Default::config{$_} || (Config::Default->can($_) && Config::Default->can($_)->()) )
               )
            || die "Found no config value for $_ in $class or Config::Default"; }
      @order;
    local @$config{keys %$config} = values %$config; # anything set in config at this point is unalterable
    $class->initialize($config);
    for my $name (@order) {
        my $a = $config->{$name}; # copy before so it cannot override itself
        $class->_load_section($name, $config);
        @$config{keys %$a} = values %$a if ref($a) eq 'HASH'; # allow for overriding entire sections
    }
    $class->finalize($config);
    map { $config->{$_} or die "Config key $_ not found in $class", } @{ $class->check_keys }
      if $class->can('check_keys');
    return $config;
}

1;

__END__

=pod

=begin readme text

Config::Cascading version 0.001

=end readme

=for readme stop

=head1 NAME

Config::Cascading - multi-level per-application config loading

=head1 VERSION

This document describes Config::Cascading version 0.001

=begin readme

=head1 INSTALLATION

To install this module, run the following commands:

    perl Makefile.PL
    make
    make test
    make install

This method of installation will require a current version of Module::Build
if it is not already installed.

Alternatively, to install with Module::Build, you can use the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

=end readme

=for readme stop

=head1 SYNOPSIS

    package config::some_config;

    use base qw(Config::Cascading);
    #our $config = __PACKAGE__->load; # uncomment to set general config at load time

    sub load_order { [qw(provider server_flavor server_type)] } # default is only server_type

    sub initialize {
        my ($class, $config) = @_;
        $config->{'default_value_for_all_brands'} = 'blah';
    }

    sub finalize { # optional
        my ($class, $config) = @_;
        # check for key setting
    }

    sub live { # will be used for server_type live rather than from config::some_config::live
        my ($class, $config) = @_;
        $config->{'live_thing'} = 'foo';
    }

    1;


    # in some other package
    use config::some_config;
    my $config = config::some_config->load;
    # OR
    use config::some_config qw($some_config); # will be in our $some_config


    # use the config from another stage
    my $config = config::some_config->load({server_type => 'live'});


=head1 DESCRIPTION

The Config::Cascading module allows for easy overridable configuration creation.
This module allows for cascaded loading where you can specify a load order such
as provider, server_flavor, server_type, and each of the those areas will
be loaded as a configuration area with each subsequent loaded area able to
override existing values (sort of like CSS rules).

A master override file can also be provided which can be set locally on the
box (outside of version control) and any values set by it win.

=head1 METHODS

Generally all methods are class methods.

=over 4

=item load_order

Return an arrayref of areas to cascade through.  Default is C<[qw(server_type)]>.
If you have different requirements, you may do something like this:

    sub load_order { [qw(server_flavor server_type)] }

Each of the items of load order is used as a key to look for the appropriate value.
At first these values are searched for from within the override file for this config.
If no value is found, the root config (use config) is loaded and the value is searched
for there.  If no value can be found for the value, the system dies.

=item load

Returns a hashref of loaded config values.  Each item of load_order is
loaded in turn.  If nothing is passed to load, it will use the values
found inside of config::$module::override.

    my $config = config::baz->load; # platform default

    my $config = config::baz->load({server_type => 'dev'});

=item check_keys

Optional - return an arrayref of key names that must be present and true in the fully formed hash.
You can run your own checks by providing a finalize routine (such as if you wanted to allow present
but false values).

=item initialize

Gets passed a hashref of values that are currently in the configuration that can be changed or
added to.

This is called for the initial subclass, C<[subclass]::override> (if there is not an C<override>
method in the initial subclass), and each C<[subclass]::[value]>, (if there is not an C<[value]>
method in the initial subclass) where [value] is the value of a key that was named in the
C<load_order> method.

=item finalize

Gets passed a hashref of values that are currently in the configuration that can be changed or
added to.

This is called only from the initial subclass (not from any modules that are loaded during the
cascading process) and is called after all other modules and methods are loaded.

=item force_section

If this method returns true, it forces an error if a method or file does not exist for the
cascaded-to section passed to it.

=back

=head1 EXAMPLE config

This sample represents using Config::Cascading as the parent for the root
config on the system

    # file config.pm
    ------------------------------------
    package config;
    use base qw(Config::Cascading);
    my $config = __PACKAGE__->load;
    our %config = %$config;

    sub initialize {
        my ($class, $config) = @_;
        $config->{'system_wide_value'} = 1;
    }

    1;

    # file config/override.pm
    ------------------------------------
    package config::override;
    sub initialize {
        my ($class, $config) = @_;
        $config->{'server_type'} = 'alpha';
        $config->{'server_wide_value'} = 'i win';
    }

    1;

    # file config/live.pm
    ------------------------------------
    package config::live;
    sub initialize {
        my ($class, $config) = @_;
        $config->{'hostname'} = 'livehost';
    }

    1;

    # file config/alpha.pm
    ------------------------------------
    package config::alpha;
    sub initialize {
        my ($class, $config) = @_;
        $config->{'hostname'} = 'alphahost';
    }

    1;

=head1 EXAMPLE config::foo

    # file config/foo.pm
    ------------------------------------
    package config::foo
    use strict;
    use base qw(Config::Cascading);

    sub initialize {
        my ($class, $config) = @_;
        $config->{'foo_value'} = 'bars';
    }

    # file config/foo/alpha.pm
    ------------------------------------
    use config::foo::alpha;
    use strict;
    sub initialize {
        my ($class, $config) = @_;
        $config->{'foo_value'} = 'bazz';
    }

    # file config/foo/override.pm
    ------------------------------------
    use config::foo::alpha;
    use strict;
    sub initialize {
        my ($class, $config) = @_;
        $config->{'foo_pass'} = 'word';
    }

=head1 DIAGNOSTICS

=over

=item C<< Cannot import config into %s >>

The variable name given to import to was invalid.

=item C<< Failed to execute %s: ... >>

A subclass of this module was defined, and it has a method named by the value of a key in
C<load_order>, but the method died.

=item C<< Could not find $INC{$s} >>

A subclass of this module was defined, but this module could not find the file it was loaded
from in order to determine where to load other files from.

=item C<< Could not find full name for %s from %s >>

A subclass of this module was defined, and was able to get a value from one of the keys defined
in the C<load_order> method, but this module could not find the file to load from that value.

=item C<< Failed to load %s: ... >>

A subclass of this module was defined, and it has a package below it named by the value
of a key in C<load_order>, but the package died when it was loaded or when its C<initialize>
method was called.

This is only returned if the C<force_section> method returns true.

=item C<< Found no config value for %s in %s or Config::Default >>

A key was specified in the C<load_order> method, but after the C<[subclass]::override>
and C<Config::Default> modules were loaded, no value could be found for that key.

=item C<< Config key %s not found from %s >>

A C<check_keys> method was provided, but one of the keys to be checked for
did not exist when the configuration finished loading.

=back

=head1 CONFIGURATION AND ENVIRONMENT

Config::Cascading requires no configuration files or environment variables of its own.
It will load a module called L<config> if no C<::override> module is available for a
subclass in order to retrieve initial values for the keys returned from the C<load_order>
method.

=for readme continue

=head1 DEPENDENCIES

Config::Cascading has no dependencies.

=for readme stop

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported yet.

Bugs should be reported via:

1) The CPAN bug tracker at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Config-Cascading>
if you have an account there.

2) Email to E<lt>bug-Config-Cascading@rt.cpan.orgE<gt> if you do not.

=head1 AUTHORS

Paul Seamons <rhandom@cpan.org>, Curtis Jewell <csjewell@cpan.org>

=for readme continue

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2013, 2014, BlueHost.com.

This module is free software; you can redistribute it and/or modify it under the same terms as
Perl itself, either version 5.6.1 or any later version. See L<perlartistic|perlartistic>
and L<perlgpl|perlgpl>.

The full text of the license can be found in the LICENSE file included with this module.

=for readme stop

