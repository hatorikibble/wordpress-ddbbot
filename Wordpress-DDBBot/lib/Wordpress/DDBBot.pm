package Wordpress::DDBBot;

=head1 NAME

Wordpress::DDBBot - automatically create WordPress Posts with DDB items

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Wordpress::DDBBot;

    my $foo = Wordpress::DDBBot->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 METHODS

=cut

use strict;
use warnings;
use namespace::autoclean;

use utf8;

use FindBin qw($Bin);
use Log::Log4perl qw( :levels);

use Encode;
use File::Slurp;
use JSON;
use List::Util qw( shuffle);
use LWP::Simple qw(get $ua);
use Switch;
use Template;
use URI::Escape;
use WordPress::XMLRPC;

use Data::Dumper;

our $VERSION = '0.9';

use Moose;
with
  qw( MooseX::Getopt MooseX::Log::Log4perl MooseX::Daemonize MooseX::Runnable   );

use Moose::Util::TypeConstraints;

subtype 'File', as 'Str',
  where { -e $_ },
  message { "Cannot find any file at $_" };

has 'debug'                => ( is => 'ro', isa => 'Bool', default  => 0 );
has 'dont_close_all_files' => ( is => 'ro', isa => 'Bool', default  => 1 );
has 'name'                 => ( is => 'ro', isa => 'Str',  required => 1 );
has 'ddb_api_key'          => ( is => 'ro', isa => 'Str',  required => 1 );
has 'ddb_api_url'          => ( is => 'ro', isa => 'Str',  required => 1 );
has 'wordpress_blog'       => ( is => 'ro', isa => 'Str',  required => 1 );
has 'wordpress_user'       => ( is => 'ro', isa => 'Str',  required => 1 );
has 'wordpress_password'   => ( is => 'ro', isa => 'Str',  required => 1 );
has 'user_agent' => ( is => 'ro', isa => 'Str', default => "EuropeanaBot" );
has 'location_file' => ( is => 'ro', isa => 'File', required => 1 );

has 'sleep_time' => ( is => 'ro', isa => 'Int', default => 2000 );

no Moose::Util::TypeConstraints;

Log::Log4perl::init( $Bin . '/logging.conf' );

=head2 run

called by the perl script

=cut

sub run {
    my $self = shift;
    $self->start();
    exit(0);
}

after start => sub {
    my $self       = shift;
    my $result_ref = undef;
    my @seeds      = ();
    my $range      = 100;
    my $random     = undef;

    return unless $self->is_daemon;

    $self->log->info("Daemon started..");

    $self->createLocationSeeds();

    while (1) {

        # what shall we do? let's roll the dice?
        $random = int( rand($range) );
        eval {
            switch ($random) {
                case [ 0 .. 99 ] {
                    $self->writeLocationPost();
                }

            }
        };
        if ($@) {
            $self->log->error( "Oh problem!: " . $@ );
        }
        else {

            $self->log->debug(
                "I'm going to sleep for " . $self->sleep_time . " seconds.." );
            sleep( $self->sleep_time );
        }

    }

};

after status => sub {
    my $self = shift;
    $self->log->info("Status check..");
};

before stop => sub {
    my $self = shift;
    $self->log->info("Daemon ended..");
};

=head2 createLocationSeeds()

reads the contents of C<$self->location_file> 
and creates C<$self->{LocationSeeds}>

=cut

sub createLocationSeeds {
    my $self      = shift;
    my @lines     = ();
    my @locations = ();

    $self->log->debug( "Creating seeds from file: " . $self->location_file );
    eval { @lines = read_file( $self->location_file ); };
    if ($@) {
        $self->log->error(
            "Cannot read seed_file " . $self->location_file . ": " . $@ );
        return \@lines;
    }
    else {

        #cleanup
        foreach my $line (@lines) {
            chomp($line);

# "07","Rheinland-Pfalz","07132058","Isert","  145","  78","  67","  181","  109","  72",-  36,"-19,9"
            if ( $line =~ /^"\d+",".*?","\d+",(.*?),"/ ) {
                push( @locations, $1 );
            }

        }

        $self->log->debug( scalar(@locations) . " searchterms generated" );
        $self->{LocationSeeds} = \@locations;
    }

} ## end sub createSeed

=head2 getDDBResults(Query=>'Linz', Field=>'title', Type=>'IMAGE', Rows=>10)

searches Europeana and returns the first matching Result

Parameters

=over 

=item  * Query

querystring for the search

=item * Field

which index to use

=item * Type

type of result, defaults to  I<mediatype_002> (image)

=items * Rows

how many rows should be returned, defaults to C<1>

=back

=cut

sub getDDBResults {
    my ( $self, %p ) = @_;
    my $json_result  = undef;
    my $result_ref   = undef;
    my $query_string = undef;
    my @items        = ();
    my $return       = undef;

    $p{Type} = 'mediatype_002' unless ( defined( $p{Type} ) );
    $p{Rows} = 20 unless ( defined( $p{Rows} ) );

    $self->log->debug( "Query: " . $p{Query} );

    #build $query_string
    eval {
        $query_string = sprintf(
"%s/search?oauth_consumer_key=%s&rows=%s&query=%s:%s&facet=type_fct&type_fct=%s",
            $self->ddb_api_url, $self->ddb_api_key, $p{Rows}, $p{Field},
            uri_escape_utf8( $p{Query} ),
            $p{Type}
        );
    };

    if ($@) {
        $self->log->error( "Error while creating query string: " . $@ );
        $return->{Status} = "NotOK";
        $return->{Query}  = $p{Query};
        return $return;
    }

    $self->log->debug( "QueryString is: " . $query_string );
    if ( $json_result = get $query_string) {
        $result_ref = decode_json($json_result);
        $self->log->debug(
            "Found " . $result_ref->{numberOfResults} . " items.." );
        if ( $result_ref->{numberOfResults} > 0 ) {

            # items found, now get an item view for a random result
            @items = shuffle( @{ $result_ref->{results}->[0]->{docs} } );

            $self->log->info( "get item " . $items[0]->{id} );

            # $self->log->debug( "Item is: " . Dumper( $items[0] ) );

            # collect some information
            foreach my $key (qw(id thumbnail category)) {
                $return->{$key} = $items[0]->{$key}
                  unless ( $key eq 'thumbnail'
                    && $items[0]->{$key} =~ /placeholder/ );
            }

            # no thumbnail, no post..
            unless ( defined( $return->{thumbnail} ) ) {
                $self->log->error("Item has no thumbnail...");
                $return->{Status} = "NotOK";
                $return->{Query}  = $p{Query};
                return $return;
            }

            eval {
                $query_string =
                  sprintf( "%s/items/%s/view?oauth_consumer_key=%s",
                    $self->ddb_api_url, $items[0]->{id}, $self->ddb_api_key );
            };

            if ($@) {
                $self->log->error( "Error while creating query string: " . $@ );
                $return->{Status} = "NotOK";
                $return->{Query}  = $p{Query};
                return $return;
            }

            $self->log->debug( "Querystring for item is: " . $query_string );

            if ( $json_result = get $query_string) {
                $result_ref = decode_json($json_result);

                $self->log->debug( "Found item" . Dumper($result_ref) );

                # collect more information
                foreach my $key (qw(origin institution title)) {
                    $return->{$key} = $result_ref->{item}->{$key};
                }

                # get direct link to item
                if (   ( defined( $return->{origin} ) )
                    && ( $return->{origin} =~ /href="(.*?)"/ ) )
                {
                    $return->{url} = $1;
                }

                # parse more fields
                foreach
                  my $field ( @{ $result_ref->{item}->{fields}->{field} } )
                {

                    switch ( $field->{name} ) {
                        case 'Urheber' { $return->{author} = $field->{value}; }
                        case 'Geschaffen (von wem)' {
                            $return->{author} = $field->{value};
                        }
                        case 'Bestand' {
                            $return->{collection} = $field->{value};
                        }
                        case 'Archivalientyp' {
                            $return->{type} = $field->{value};
                        }
                        case 'Laufzeit' { $return->{date} = $field->{value}; }
                        case 'Geschaffen (wann)' {
                            $return->{date} = $field->{value};
                        }
                        case 'Schlagwort' {
                            $return->{keywords} = $field->{value};
                        }
                    }
                }

                # custom enrichment
                $return->{Status} = "OK";
                $return->{Query}  = $p{Query};
                $self->log->debug( "Assembled result: " . Dumper($return) );

                return $return;
            }
            else {
                $return->{Status} = "NotOK";
                $return->{Query}  = $p{Query};
                return $return;
            }

        }
        else {
            $return->{Status} = "NotOK";
            $return->{Query}  = $p{Query};
            return $return;
        }

    }

}

=head2 writeLocationPost()

posts a search result from the Location Tweet file

=cut

sub writeLocationPost {
    my $self       = shift;
    my $result_ref = undef;
    my @seeds      = shuffle @{ $self->{LocationSeeds} };

    $self->log->debug("Blogging about a location!");

    foreach my $term (@seeds) {

        $result_ref = $self->getDDBResults(
            Query => $term,
            Field => 'title',
            Rows  => 10
        );
        if ( $result_ref->{Status} eq 'OK' ) {
            $self->post2Wordpress( Result => $result_ref );
            return;
        }
    }
}

=head2 post2Wordpress(Result=>$result)

posts the result to the twitter account specified by C<$self->twitter_account>

Parameters

=over


=item  * Result

DDB Search Result

=back

=cut

sub post2Wordpress {
    my ( $self, %p ) = @_;
    my $template   = undef;
    my $output     = undef;
    my $cat_found  = "false";
    my @categories = ();
    my $return     = undef;
    my $post_id    = undef;
    my $TTemplate  = Template->new();
    my $WordPress  = WordPress::XMLRPC->new(
        {
            username => $self->wordpress_user,
            password => $self->wordpress_password,
            proxy    => $self->wordpress_blog . '/xmlrpc.php',
        }
    );

    # Hack
    $p{Result}->{Query} = decode( 'utf-8', $p{Result}->{Query} );

    $template = <<"EOT";
<p>Ich hab da mal was [% IF Result.date %] aus <b>[% Result.date %]</b>[% END %] gefunden...
[% IF Result.author %]<br>Als Urheber wird <b>[% Result.author %]</b> angegeben.[% END %]
</p>
<a href="[% Result.url %]" target="_blank"><img src="http://www.deutsche-digitale-bibliothek.de[% Result.thumbnail %]" alt="[% Result.title %]"/></a>
<p>Das Original stammt aus <b><a href="[% Result.institution.url %]" target="_blank">[% Result.institution.name %]</a></b> und kann unter [% Result.origin %] angeschaut werden.</p>
<p>Gesucht habe ich übrigens mit [% Result.Query %].</p>
<p><i>Naja, ich schau dann mal weiter...</i></p>
EOT

    $TTemplate->process( \$template, \%p, \$output )
      || $self->log->error(
        "Could not create template: " . $TTemplate->error() );
    $self->log->debug( "Output: " . $output );

    # check category and use type also as category

    foreach my $item ( ( $p{Result}->{category}, $p{Result}->{type} ) ) {
        $cat_found = "false";
        if ( defined($item) ) {

            foreach my $cat ( @{ $WordPress->getCategories() } ) {
                if ( $cat->{categoryName} eq $item ) {
                    $cat_found = "true";
                }
            }

            if ( ( $cat_found eq 'false' ) && ( $self->debug != 1 ) )
            {    # create new category
                $self->log->info( "Creating category: " . $item );
                $return = $WordPress->newCategory( { name => $item } );
                unless ( $return =~ /^\d+$/ ) {
                    $self->log->error( "Could not create category: " . $item );

                }
            }
            push( @categories, encode( 'utf-8', $item ) );
        }

    }

    # Tags
    $p{Result}->{keywords} =~ s/;/,/g;

    $self->log->debug(
        "Poste Eintrag:" . $output . "debug ist: " . $self->debug );

    unless ( $self->debug == 1 ) {

        $post_id = $WordPress->newPost(
            {
                title       => encode( 'utf-8', $p{Result}->{title} ),
                description => encode( 'utf-8', $output ),
                mt_keywords => encode( 'utf-8', $p{Result}->{keywords} ),
                categories  => \@categories,
            },
            1
        );
        if ( $post_id =~ /^\d+$/ ) {
            $self->log->info( "Post with the id " . $post_id . " created" );
        }
        else {

            $self->log->error( "Could not createblog post: " . $post_id );

        }

    }

}

=head1 AUTHOR

Peter Mayr, C<< <at.peter.mayr at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-wordpress-ddbbot at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Wordpress-DDBBot>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Wordpress::DDBBot


You can also look for information at:

=over 4

=item * GitHub

L<https://github.com/hatorikibble/wordpress-ddbbot>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Peter Mayr.

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

1;    # End of Wordpress::DDBBot
