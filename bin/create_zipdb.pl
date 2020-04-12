#!/usr/bin/env perl
#===============================================================================
#
#         FILE: create_zipdb.pl
#
#        USAGE: ./create_zipdb.pl --new_zipdb
#
#  DESCRIPTION: This script merges two NYC Zip Code Data structures
#               to create a simple JSON NYC Zip code database.
#
#       AUTHOR: Austin Kenny (AK), aibistin.cionnaith@gmail.com
# ORGANIZATION: Me
#      VERSION: 1.0
#      CREATED: 04/10/2020
#===============================================================================
use strict;
use warnings;
use utf8;
use v5.22;
use Moo;
use MooX::Options;
use Data::Dump qw/dump/;
use Path::Tiny qw/path/;
use FindBin qw/$Bin/;
use lib "$Bin/../lib";
use ZipDb;

#-------------------------------------------------------------------------------
my $THIS_SCRIPT = path($0)->basename;

#-------------------------------------------------------------------------------
# Options
#-------------------------------------------------------------------------------
option create_zip_db => (
    is    => 'ro',
    short => 'new_zipdb|new_zip|n',
    doc   => q/Create a new NYC Zip, Borough, District, Town JSON file./,
);

option read_zip_db => (
    is    => 'ro',
    short => 'read|r',
    doc   => q/Read the NYC Zip file database./,
);

option get_details => (
    is        => 'ro',
    format    => 's@',
    autosplit => ',',
    default   => sub { [] },
    short     => 'details',
    doc       => q/Get the available details of a given zip code or codes/,
    long_doc  => qq{
        Get the available details of a given zip code
        $THIS_SCRIPT --get_details 11379,11104
        # Will print the following to the console
            [
                {
                    11379 => {
                    borough  => "Queens",
                    city     => "Middle Village",
                    county   => "Queens",
                    district => "West Central Queens",
                    },
                },
                {
                    11104 => {
                    borough  => "Queens",
                    city     => "Sunnyside",
                    county   => "Queens",
                    district => "Northwest Queens",
                    },
                },
            ]
         }
);

option get_zips => (
    is     => 'ro',
    format => 's',
    short  => 'zips',
    doc    => q/Get the zip codes, from city details/,
);

option db_dir => (
    is      => 'ro',
    format  => 's',
    short   => 'dir|d',
    default => sub { "$Bin/../db" },
    doc     => qq{Specify a database directory. The default is '$Bin/../db'},
);

option verbose => (
    is    => 'ro',
    short => 'v',
    doc   => 'Print more stuff',
);

#===============================================================================
# Main
#===============================================================================
sub run {
    my ($self) = @_;

    my $zip_db = ZipDb->new( db_dir => $self->db_dir );

    if ( $self->create_zip_db ) {
        $zip_db->create_new_zipdb_file;
        say "Created a new " . $zip_db->zip_db_json_file if $self->verbose;
    }

    if ( $self->read_zip_db ) {
        my $db_data = $zip_db->read_the_db;
        dump $db_data if $self->verbose;
    }

    if ( @{ $self->get_details } ) {
        my $z_details = $zip_db->get_zip_details( $self->get_details );
        dump $z_details;
    }

    if ( $self->get_zips ) {
        my $zip_codes =
          $zip_db->get_zip_codes_matching_details( $self->get_zips );
        dump $zip_codes;
    }
    say "All Done!" if $self->verbose;
}

main->new_with_options()->run;

#-------------------------------------------------------------------------------
#  END
#-------------------------------------------------------------------------------
1;
