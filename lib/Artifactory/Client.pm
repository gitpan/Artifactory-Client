package Artifactory::Client;

use strict;
use warnings;
use Moose;
use LWP::UserAgent;
use Data::Dumper;
use URI::Escape;
use namespace::autoclean;

=head1 NAME

Artifactory::Client - Perl client for Artifactory REST API

=head1 VERSION

Version 0.0.12

=cut

our $VERSION = '0.0.12';

=head1 SYNOPSIS

    This is a Perl client for Artifactory REST API: https://www.jfrog.com/confluence/display/RTF/Artifactory+REST+API

    use Artifactory::Client;
    
    my $args = {
        artifactory => 'http://artifactory.server.com',
        port => 8080,
        repository => 'myrepository',
        ua => LWP::UserAgent->new() # LWP::UserAgent-like object is pluggable
    };

    my $client = Artifactory::Client->new( $args );
    my $path = '/foo'; # path on artifactory
    
    # Properties are key-multi-value pairs.  Values must be an arrayref even for a single element.
    my $properties = {
        one => ['two'],
        baz => ['three'],
    };
    my $content = "content of artifact";

    # Name of methods are taken straight from Artifactory REST API documentation.  'Deploy Artifact' would map to
    # deploy_artifact method, like below.  The caller gets HTTP::Response object back.
    my $resp = $client->deploy_artifact( path => $path, properties => $properties, content => $content );

    # Custom requests can also be made via usual get / post / put / delete requests.
    my $resp = $client->get( 'http://artifactory.server.com/path/to/resource' );

    Note on testing:
    This module was developed using Test-Driven Development.  Due to the nature of talking to 3rd-party API, I wrote
    functional tests first.  Because the tests contain proprietary information for my employer, I am not allowed to
    distribute them on CPAN.  When I get a chance I should mock the functional tests into unit tests.  Meanwhile here is
    the coverage information from the functional tests:
    ----------------------------------- ------ ------ ------ ------ ------ ------
    File                                  stmt   bran   cond    sub   time  total
    ----------------------------------- ------ ------ ------ ------ ------ ------
    lib/Artifactory/Client.pm             94.3   80.0    n/a   88.9   30.4   91.8
    01_client.t                          100.0    n/a    n/a  100.0   69.6  100.0
    Total                                 97.7   80.0    n/a   94.6  100.0   96.4
    ----------------------------------- ------ ------ ------ ------ ------ ------

=cut

has 'artifactory' => (
    is => 'ro',
    isa => 'Str',
    required => 1
);

has 'port' => (
    is => 'ro',
    isa => 'Int',
    default => 80
);

has 'ua' => (
    is => 'ro',
    isa => 'LWP::UserAgent',
    builder => '_build_ua'
);

has 'repository' => (
    is => 'ro',
    isa => 'Str',
    required => 1
);

=head1 SUBROUTINES/METHODS

=cut

sub _build_ua {
    my $self = shift;
    $self->{ ua } = LWP::UserAgent->new() unless( $self->{ ua } );
}

=head2 get

    Invokes GET request on LWP::UserAgent-like object; params are passed through.
    Returns HTTP::Response object.

=cut

sub get {
    my ( $self, @args ) = @_;
    return $self->_request( 'get', @args );
}

=head2 post

    Invokes POST request on LWP::UserAgent-like object; params are passed through.
    Returns HTTP::Response object.

=cut

sub post {
    my ( $self, @args ) = @_;
    return $self->_request( 'post', @args );
}

=head2 put

    Invokes PUT request on LWP::UserAgent-like object; params are passed through.
    Returns HTTP::Response object.

=cut

sub put {
    my ( $self, @args ) = @_;
    return $self->_request( 'put', @args );
}

=head2 delete

    Invokes DELETE request on LWP::UserAgent-like object; params are passed through.
    Returns HTTP::Response object.

=cut

sub delete {
    my ( $self, @args ) = @_;
    return $self->_request( 'delete', @args );
}

sub _request {
    my ( $self, $method, @args ) = @_;
    return $self->{ ua }->$method( @args );
}

=head2 deploy_artifact

    Takes hash of path, properties and content then deploys artifact as specified in Deploy Artifact section of
    Artifactory REST API documentation.  Note that properties are key-multi-value pairs where the value is an arrayref.
    Returns HTTP::Response object.

=cut

sub deploy_artifact {
    my ( $self, %args ) = @_;
    my ( $artifactory, $port, $repository ) = $self->_unpack_attributes( 'artifactory', 'port', 'repository' );

    my $path = $args{ path };
    my $properties = $args{ properties };
    my $content = $args{ content };
    my $url = "$artifactory:$port/artifactory/$repository$path;";

    my $request = $self->_attach_properties( url => $url, properties => $properties, matrix => 1 );
    return $self->put( $request, content => $content );
}

=head2 set_item_properties

    Takes hash of path and properties then set item properties as specified in Set Item Properties section of
    Artifactory REST API documentation.  Note that properties are key-multi-value pairs where the value is an arrayref.
    Returns HTTP::Response object.

=cut

sub set_item_properties {
    my ( $self, %args ) = @_;
    my ( $artifactory, $port, $repository ) = $self->_unpack_attributes( 'artifactory', 'port', 'repository' );

    my $path = $args{ path };
    my $properties = $args{ properties };
    my $url = "$artifactory:$port/api/storage/$repository$path?properties=";
    my $request = $self->_attach_properties( url => $url, properties => $properties );

    return $self->put( $request );
}

sub _unpack_attributes {
    my ( $self, @args ) = @_;
    my @result;

    for my $attr ( @args ) {
        push @result, $self->{ $attr };
    }
    return @result;
}

sub _attach_properties {
    my ( $self, %args ) = @_;
    my $url = $args{ url };
    my $properties = $args{ properties };
    my $matrix = $args{ matrix };

    for my $key ( keys %{ $properties } ) {
        $url .= $self->_handle_prop_multivalue( $key, $properties->{ $key }, $matrix );
    }
    return $url;
}

sub _handle_prop_multivalue {
    my ( $self, $key, $values, $matrix ) = @_;

    # need to handle matrix vs non-matrix situations.
    # if matrix, string looks like key=val;key=val2;key=val3;
    # if non-matrix, string looks like key=val1,val2,val3|
    my $str = ( $matrix ) ? '' : "$key=";

    for my $val ( @{ $values } ) {
        $val = '' if ( !defined $val );
        $val = uri_escape( $val );
        $str .= ( $matrix ) ? "$key=$val;" : "$val,";
    }
    $str .= ( $matrix ) ? '' : "|";
    return $str;
}

__PACKAGE__->meta->make_immutable;

=head1 AUTHOR

Satoshi Yagi, C<< <satoshi at yahoo-inc.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-artifactory-client at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Artifactory-Client>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Artifactory::Client

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Artifactory-Client>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Artifactory-Client>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Artifactory-Client>

=item * Search CPAN

L<http://search.cpan.org/dist/Artifactory-Client/>

=back

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2014, Yahoo! Inc.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1; # End of Artifactory::Client
