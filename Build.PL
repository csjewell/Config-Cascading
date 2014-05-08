use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
    class => 'My::Builder',
    code  => <<'END_CODE',
sub ACTION_authortest {
    my ($self) = @_;

    $self->depends_on('build');

    $self->test_files( qw( t xt/author ) );
    $self->depends_on('test');

    return;
}

sub ACTION_releasetest {
    my ($self) = @_;

    $self->depends_on('build');

    $self->test_files( qw( t xt/author xt/release ) );
    $self->depends_on('test');

    return;
}

sub ACTION_manifest {
    my ($self, @arguments) = @_;

    if (-e 'MANIFEST') {
        unlink 'MANIFEST' or die "Can't unlink MANIFEST: $!";
    }

    return $self->SUPER::ACTION_manifest(@arguments);
}

sub ACTION_distmeta {
    my ($self) = @_;

    $self->depends_on('manifest');

    return $self->SUPER::ACTION_distmeta();
}
END_CODE
);

my $builder = $class->new(
    module_name         => 'Config::Cascading',
    license             => 'perl',
    dist_author         => [ 'Curtis Jewell <csjewell@cpan.org>' ],
    dist_version_from   => 'lib/Config/Cascading.pm',
    create_readme       => 1,
    create_license      => 1,
    create_makefile_pl  => 'small',
    configure_requires  => {
        'Module::Build' => '0.3614',
    },
    requires            => {
        'perl'          => '5.006001',
    },
    build_requires      => {
        'Test::More'    => '0.88',
    },
    meta_merge    => {
        resources => {
            bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Config-Cascading',
            repository => 'https://github.com/csjewell/Config-Cascading',
        },
    },
    add_to_cleanup      => [ 'Config-Cascading-*', ],
);

$builder->create_build_script();
