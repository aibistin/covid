#!/usr/bin/env perl
#===============================================================================
#
#         FILE: city_covid_data.pl
#
#        USAGE: ./city_covid_data.pl
#
#  DESCRIPTION:
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Austin Kenny (AK), aibistin.cionnaith@gmail.com
# ORGANIZATION: Me
#      VERSION: 1.0
#      CREATED: 04/01/2020
#     REVISION: ---
#===============================================================================
use strict;
use warnings;
use utf8;
use autodie;
use v5.22;
use Moo;
use MooX::Options;
use Path::Tiny qw/path/;
use Data::Dump qw/dump/;
use List::Util qw/any/;
use Types::Path::Tiny qw/Path AbsPath/;
use File::Serialize qw/serialize_file deserialize_file/;
use Time::Piece;
use Chart::Plotly::Trace::Histogram;
use HTML::Show;
use Chart::Plotly;
use Chart::Plotly::Trace::Histogram;
use Capture::Tiny qw/capture/;
use LWP::Simple;
use Text::CSV_XS;
use FindBin qw/$Bin/;
use lib "$Bin/../lib";
use ZipDb;

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
my $RAW_ZCTA_DATA_LINK =
q{https://raw.githubusercontent.com/nychealth/coronavirus-data/master/tests-by-zcta.csv};
my $NA_ZIP            = '88888';
my $START_DATE        = '20200401';         # April 1, the perfect starting date
my $ALL_ZCTA_DATA_CSV = 'all_zcta_data.csv';

#-------------------------------------------------------------------------------
# Options
#-------------------------------------------------------------------------------
option write_zcta_to_csv => (
    is    => 'ro',
    short => 'zcta_to_csv|z_to_c|c',
    doc   => qq{Print latest ZCTA data to csv, 'output/$ALL_ZCTA_DATA_CSV'},
);

option create_new_zcta_db => (
    is    => 'ro',
    short => 'new_zcta|new_z|n',
    doc =>
      q/Create a new NYC Zip Cumulative Test 'A' JSON db for todays result/,
);

option verbose => (
    is    => 'ro',
    doc   => 'Print details',
    short => 'v',
);

#-------------------------------------------------------------------------------
# Attributes
#-------------------------------------------------------------------------------
# ZCTA = Zip Cumulative Test something or other
has zcta_github_link => (
    is      => 'ro',
    default => $RAW_ZCTA_DATA_LINK
);

has tests_by_zcta_db_json_file => (
    is      => 'lazy',
    isa     => Path,
    builder => sub {
        my $self       = shift;
        my %dates      = %{ _get_date_h() };
        my $db_sub_dir = $self->db_dir->child( $dates{yyyy_mm} );
        $db_sub_dir->mkpath unless ( -d $db_sub_dir );
        my $file_name = $dates{yyyymmdd} . "_tests_by_ztca.json";

        # my $file_name = '20200401' . "_tests_by_ztca.json";
        $db_sub_dir->child($file_name);
    }
);

has tests_by_zcta_today => (
    is  => 'lazy',
    isa => sub {
        die "'tests_by_zcta_today' must be an ARRAY"
          unless ( ref( $_[0] ) eq 'ARRAY' );
    },
    builder => sub {
        my $self = shift;
        die $self->tests_by_zcta_db_json_file
          . " doesn't exist! Run this script with the 'create_new_zcta_db' option"
          unless ( -e $self->tests_by_zcta_db_json_file );
        deserialize_file $self->tests_by_zcta_db_json_file;
    }
);

has all_tests_by_zcta_data => (
    is  => 'lazy',
    isa => sub {
        die "'all_tests_by_zcta_data' must be an ARRAY"
          unless ( ref( $_[0] ) eq 'ARRAY' );
    },
    builder => sub {
        my $self = shift;
        my @all_data;
        for my $folder ( $self->db_dir->children(qr/\d{4}_\d{2}/) ) {
            for my $file ( $folder->children(qr/tests_by_ztca/) ) {
                my $one_days_data = deserialize_file $file;
                push @all_data, $one_days_data;
            }
        }
        return \@all_data;
    }
);

has zip_hash => (
    is => 'lazy',
    isa =>
      sub { die "'zip_hash' must be a HASH" unless ( ref( $_[0] ) eq 'HASH' ) },
    builder => sub {
        my $zip_db = ZipDb->new( db_dir => "$Bin/../db" );
        return $zip_db->zip_db_hash;
    }
);

#===============================================================================
# Main
#===============================================================================
sub run {
    my ($self) = @_;

    $self->create_latest_tests_by_ztca_file if $self->create_new_zcta_db;
    $self->create_zcta_view                 if $self->create_new_zcta_db;

    $self->write_latest_zcta_to_csv if $self->write_zcta_to_csv;
    my $histogram =
      Chart::Plotly::Trace::Histogram->new(
        x => [ map { int( 10 * rand() ) } ( 1 .. 500 ) ] );

  # HTML::Show::show( Chart::Plotly::render_full_html( data => [$histogram] ) );

    # dump $covid_data;

}

main->new_with_options()->run;

#===============================================================================
# Methods
#===============================================================================

sub write_latest_zcta_to_csv {
    my ($self) = @_;
    my @col_headers = (
        qw/Zip Date City District Borough/,
        'Total Tested', 'Positive', '% of Tested'
    );
    my @col_names = (
        qw/zip yyyymmdd city district borough total_tested positive cumulative_percent_of_those_tested /
    );
    my $csv       = Text::CSV_XS->new( { binary => 1, eol => $/ } );
    my $zcta_file = $self->get_todays_csv_file($ALL_ZCTA_DATA_CSV);
    my $z_fh      = $zcta_file->openw;
    $csv->print( $z_fh, \@col_headers ) or $csv->error_diag;

    for my $one_day_zip_rec (
        sort { $b->{positive} <=> $a->{positive} || $a->{zip} <=> $b->{zip} }
        @{ $self->tests_by_zcta_today } )
    {
        my $location_rec = $self->zip_hash->{ $one_day_zip_rec->{zip} }
          || _get_filler_location_rec( $one_day_zip_rec->{zip} );
        $self->zip_hash->{ $one_day_zip_rec->{zip} } ||= $location_rec;
        my %csv_rec = ( %$one_day_zip_rec, %$location_rec );
        $csv->print( $z_fh, [ @csv_rec{@col_names} ] );
    }
    close($z_fh) or warn "Failed to close $zcta_file";
    say "Created a new $zcta_file";
    `notepad++ "$zcta_file"`;
}

sub create_zcta_view {
    my $self = shift;
    my $ct;
    my @view;
    for my $one_day_tests ( @{ $self->all_tests_by_zcta_data } ) {
        my %day_view;
        for my $test_rec ( sort { $a->{zip} <=> $b->{zip} } @{$one_day_tests} )
        {
            my $location_rec = $self->zip_hash->{ $test_rec->{zip} }
              || _get_filler_location_rec( $test_rec->{zip} );
            $self->zip_hash->{ $test_rec->{zip} } ||= $location_rec;
            $day_view{ $test_rec->{zip} } = { %$test_rec, %$location_rec };
        }
        push @view, \%day_view;
    }
    my $view_file = $self->get_view_file('all_zcta_view');
    serialize_file $view_file => \@view;
    say "Created a new $view_file";
    `notepad++ "$view_file"`;
}

sub get_view_file {
    my ( $self, $view_file_name ) = @_;
    state $views_dir = $self->db_dir->child('views');
    $views_dir->mkpath unless ( -d $views_dir );
    my $view_file = $views_dir->child( $view_file_name . '.json' );
    $view_file->mkpath unless ( -f $view_file );
    return $view_file;
}

sub get_todays_csv_file {
    my ( $self, $file_name ) = @_;
    my $date_h = _get_date_h();
    return $self->db_dir->child( $date_h->{yyyymmdd} . '_' . $file_name );
}

sub create_latest_tests_by_ztca_file {
    my $self       = shift;
    my $covid_data = $self->get_raw_covid_data_by_zip();

    serialize_file $self->tests_by_zcta_db_json_file => $covid_data;
    say "Created a new " . $self->tests_by_zcta_db_json_file;
    1;
}

sub get_raw_covid_data_by_zip {
    my $self = shift;
    my @data =
      map { _conv_zcta_rec_to_hash($_) }
      split( /\r?\n/, get( $self->zcta_github_link ) );
    shift @data
      if ( $data[0]->{cumulative_percent_of_those_tested} =~ /zcta_cum/ )
      ;    # Dont need that header
    say "Got @{[ scalar @data ]} lines of covid data. Thanks Mr. Mayor";
    return \@data;
}

#-------------------------------------------------------------------------------
#   Private Methods
#-------------------------------------------------------------------------------
# Heder Line: "MODZCTA","Positive","Total","zcta_cum.perc_pos";
sub _conv_zcta_rec_to_hash {
    my $str = shift;
    state $date_h = _get_date_h();
    my %h;
    (
        $h{zip}, $h{positive}, $h{total_tested},
        $h{cumulative_percent_of_those_tested}
    ) = split /\s*,\s*/, $str;

    ( $h{zip} ) = $h{zip} =~ /(\d+)/;
    $h{zip} ||= $NA_ZIP;    # There is one undef zip in test data
    $h{yyyymmdd} = $date_h->{yyyymmdd};
    return \%h;
}

sub _get_filler_location_rec {
    my $zip = shift || $NA_ZIP;
    my $label = 'Unknown-' . $zip;
    return {
        zip        => $zip,
        'borough'  => $label,
        'city '    => $label,
        'district' => $label,
        'county', $label
    };
}

#-------------------------------------------------------------------------------
# Private Functions
#-------------------------------------------------------------------------------

sub _get_date_h {
    my $t = localtime;
    my $month_num = $t->mon < 10 ? '0' . $t->mon : $t->mon;
    {
        mon          => $t->monname,
        year         => $t->year,
        day          => $t->wdayname,                  # 'Mon'
        day_of_month => $t->day_of_month,
        day_of_year  => $t->day_of_year,
        yyyymmdd     => $t->ymd(''),
        yyyy_mm      => $t->year . '_' . $month_num,
    };
}

sub _trim {
    return $_[0] unless defined $_[0];
    $_[0] =~ s/^\s+//;
    $_[0] =~ s/\s+$//;
    $_[0];
}

#-------------------------------------------------------------------------------
#  END
#-------------------------------------------------------------------------------
1;
