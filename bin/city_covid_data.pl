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

# use Types::URI qw/Uri/;
use Capture::Tiny qw/capture/;
use LWP::Simple;
use Text::CSV_XS;
use FindBin qw/$Bin/;

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
option verbose => ( is => 'ro', doc => 'Print details' );

option write_zcta_to_csv => (
    is    => 'ro',
    short => 'zcta_to_csv|z_to_c',
    doc   => qq{Print latest ZCTA data to csv, 'output/$ALL_ZCTA_DATA_CSV'},
);

option create_new_zipdb => (
    is    => 'ro',
    short => 'new_zipdb|new_zip',
    doc   => q/Create a new NYC Zip,Borough,District,Town JSON file./,
);

option create_new_zcta_db => (
    is    => 'ro',
    short => 'new_zcta|new_z',
    doc =>
      q/Create a new NYC Zip Cumulative Test 'A' JSON db for todays result/,
);

#-------------------------------------------------------------------------------
# Attributes
#-------------------------------------------------------------------------------
has db_dir => (
    is      => 'rw',
    isa     => Path,
    coerce  => 1,
    default => sub { "$Bin/../db" }
);

# ZCTA = Zip Cumulative Test something or other
has zcta_github_link => (
    is      => 'ro',
    default => $RAW_ZCTA_DATA_LINK
);

# Database
has zip_db_json_file => (
    is      => 'lazy',
    isa     => Path,
    builder => sub {
        $_[0]->db_dir->child("zip_db.json");
    }
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

# Database data
has zip_hash => (
    is => 'lazy',
    isa =>
      sub { die "'zips_hash' must be a HASH" unless ( ref( $_[0] ) eq 'HASH' ) }
    ,
    builder => sub {
        deserialize_file $_[0]->zip_db_json_file;
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

#===============================================================================
# Main
#===============================================================================
sub run {
    my ($self) = @_;

    $self->create_new_zipdb_file if $self->create_new_zipdb;

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

    # my $covid_data = _missed_testing_date(); # To include some old data
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
#   ZIP DB
#-------------------------------------------------------------------------------
sub create_new_zipdb_file {
    my $self = shift;
    my $zd   = $self->get_raw_zip_data();
    serialize_file $self->zip_db_json_file => $zd;
}

sub get_raw_zip_data {
    my $self = shift;

    my %zips_to_city = %{ _get_zips_to_city() };
    my %bdz          = %{ _get_borough_district_zips() };
    my %zip_boro_dist;
    for my $boro ( sort keys %bdz ) {
        my %dist = %{ $bdz{$boro} };
        for my $dist_name ( sort keys %dist ) {

            # say "Dist name: $dist_name";
            my @zips = @{ $dist{$dist_name} };
            for my $zip ( sort @zips ) {
                my ( $city, $county ) = split /,/, $zips_to_city{$zip};
                $county =
                    $boro eq 'Brooklyn' ? 'Kings'
                  : $boro eq 'Bronx'    ? 'Bronx'
                  : 'New York'
                  unless $county;

                $zip_boro_dist{$zip} = {
                    borough  => $boro,
                    district => $dist_name,
                    city     => $city,
                    county   => $county,
                };
            }
        }
    }
    return \%zip_boro_dist;
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

# https://www.health.ny.gov/statistics/cancer/registry/appendix/neighborhoods.htm
# Added: 10069 => "Upper West Side"
#        10280 10282 => "Battery Park City"
#        11109 =>
sub _get_borough_district_zips {
    return {
        Bronx => {
            'Central Bronx'              => [qw/10453 10457 10460/],
            'Bronx Park and Fordham'     => [qw/10458 10467 10468/],
            'High Bridge and Morrisania' => [qw/10451 10452 10456/],
            'Hunts Point and Mott Haven' => [qw/10454 10455 10459 10474/],
            'Kingsbridge and Riverdale'  => [qw/10463 10471/],
            'Northeast Bronx'            => [qw/10466 10469 10470 10475/],
            'Southeast Bronx' => [qw/10461 10462 10464 10465 10472 10473/],
        },
        Brooklyn => {
            'Central Brooklyn'           => [qw/11212 11213 11216 11233 11238/],
            'Southwest Brooklyn'         => [qw/11209 11214 11228/],
            'Borough Park'               => [qw/11204 11218 11219 11230/],
            'Canarsie and Flatlands'     => [qw/11234 11236 11239/],
            'Southern Brooklyn'          => [qw/11223 11224 11229 11235/],
            'Northwest Brooklyn'         => [qw/11201 11205 11215 11217 11231/],
            'Flatbush'                   => [qw/11203 11210 11225 11226/],
            'East New York and New Lots' => [qw/11207 11208/],
            'Greenpoint'                 => [qw/11211 11222/],
            'Sunset Park'                => [qw/11220 11232/],
            'Bushwick and Williamsburg'  => [qw/11206 11221 11237/],
        },
        Manhattan => {
            'Central Harlem' => [qw/10026 10027 10030 10037 10039/],

           # 'Chelsea and Clinton' => [qw/10001 10011 10018 10019 10020 10036/],
            'Chelsea and Hells Kitchen' =>
              [qw/10001 10011 10018 10019 10020 10036/],
            'East Harlem'                   => [qw/10029 10035/],
            'Gramercy Park and Murray Hill' => [qw/10010 10016 10017 10022/],
            'Greenwich Village and Soho'    => [qw/10012 10014/],
            'Greenwich Village and Chinatown' => [qw/10013/],    # My addition
            'Lower Manhattan' => [qw/10004 10005 10006 10007 10038/],
            'Lower East Side' => [qw/10003 10009/],
            'Lower East Side Inc. Chinatown' => [qw/10002/],     # My addition
            'Upper East Side' => [qw/10021 10028 10044 10065 10075 10128/],
            'Upper West Side' => [qw/10023 10024 10025 10069/],
            'Inwood and Washington Heights' =>
              [qw/10031 10032 10033 10034 10040/],
            'Battery Park City' => [qw/10280 10282/],            # My addition

        },
        Queens => {
            'Northeast Queens' => [qw/11361 11362 11363 11364/],
            'North Queens'   => [qw/11354 11355 11356 11357 11358 11359 11360/],
            'Central Queens' => [qw/11365 11366 11367/],
            'Jamaica'        => [qw/11412 11423 11432 11433 11434 11435 11436/],
            'Northwest Queens' =>
              [qw/11101 11102 11103 11104 11105 11106 11109/],
            'West Central Queens' => [qw/11374 11375 11379 11385/],
            'Rockaways'           => [qw/11691 11692 11693 11694 11695 11697/],
            'Southeast Queens' =>
              [qw/11004 11005 11411 11413 11422 11426 11427 11428 11429/],
            'Southwest Queens' =>
              [qw/11414 11415 11416 11417 11418 11419 11420 11421/],
            'West Queens' => [qw/11368 11369 11370 11372 11373 11377 11378/],
        },
        'Staten Island' => {
            'Port Richmond'            => [qw/10302 10303 10310/],
            'South Shore'              => [qw/10306 10307 10308 10309 10312/],
            'Stapleton and St. George' => [qw/10301 10304 10305/],
            'Mid-Island'               => [qw/10314/],
        }
    };
}

sub _get_zips_to_city {
    return {
        '10001' => q{New York},
        '10002' => q{New York},
        '10003' => q{New York},
        '10004' => q{New York},
        '10005' => q{New York},
        '10006' => q{New York},
        '10007' => q{New York},
        '10008' => q{New York},
        '10009' => q{New York},
        '10010' => q{New York},
        '10011' => q{New York},
        '10012' => q{New York},
        '10013' => q{New York},
        '10014' => q{New York},
        '10016' => q{New York},
        '10017' => q{New York},
        '10018' => q{New York},
        '10019' => q{New York},
        '10020' => q{New York},
        '10021' => q{New York},
        '10022' => q{New York},
        '10023' => q{New York},
        '10024' => q{New York},
        '10025' => q{New York},
        '10026' => q{New York},
        '10027' => q{New York},
        '10028' => q{New York},
        '10029' => q{New York},
        '10030' => q{New York},
        '10031' => q{New York},
        '10032' => q{New York},
        '10033' => q{New York},
        '10034' => q{New York},
        '10035' => q{New York},
        '10036' => q{New York},
        '10037' => q{New York},
        '10038' => q{New York},
        '10039' => q{New York},
        '10040' => q{New York},
        '10041' => q{New York},
        '10043' => q{New York},
        '10044' => q{New York},
        '10045' => q{New York},
        '10055' => q{New York},
        '10060' => q{New York},
        '10065' => q{New York},
        '10069' => q{New York},
        '10075' => q{New York},
        '10080' => q{New York},
        '10081' => q{New York},
        '10087' => q{New York},
        '10090' => q{New York},
        '10101' => q{New York},
        '10102' => q{New York},
        '10103' => q{New York},
        '10104' => q{New York},
        '10105' => q{New York},
        '10106' => q{New York},
        '10107' => q{New York},
        '10108' => q{New York},
        '10109' => q{New York},
        '10110' => q{New York},
        '10111' => q{New York},
        '10112' => q{New York},
        '10113' => q{New York},
        '10114' => q{New York},
        '10115' => q{New York},
        '10116' => q{New York},
        '10117' => q{New York},
        '10118' => q{New York},
        '10119' => q{New York},
        '10120' => q{New York},
        '10121' => q{New York},
        '10122' => q{New York},
        '10123' => q{New York},
        '10124' => q{New York},
        '10125' => q{New York},
        '10126' => q{New York},
        '10128' => q{New York},
        '10129' => q{New York},
        '10130' => q{New York},
        '10131' => q{New York},
        '10132' => q{New York},
        '10133' => q{New York},
        '10138' => q{New York},
        '10150' => q{New York},
        '10151' => q{New York},
        '10152' => q{New York},
        '10153' => q{New York},
        '10154' => q{New York},
        '10155' => q{New York},
        '10156' => q{New York},
        '10157' => q{New York},
        '10158' => q{New York},
        '10159' => q{New York},
        '10160' => q{New York},
        '10162' => q{New York},
        '10163' => q{New York},
        '10164' => q{New York},
        '10165' => q{New York},
        '10166' => q{New York},
        '10167' => q{New York},
        '10168' => q{New York},
        '10169' => q{New York},
        '10170' => q{New York},
        '10171' => q{New York},
        '10172' => q{New York},
        '10173' => q{New York},
        '10174' => q{New York},
        '10175' => q{New York},
        '10176' => q{New York},
        '10177' => q{New York},
        '10178' => q{New York},
        '10179' => q{New York},
        '10185' => q{New York},
        '10199' => q{New York},
        '10203' => q{New York},
        '10211' => q{New York},
        '10212' => q{New York},
        '10213' => q{New York},
        '10242' => q{New York},
        '10249' => q{New York},
        '10256' => q{New York},
        '10258' => q{New York},
        '10259' => q{New York},
        '10260' => q{New York},
        '10261' => q{New York},
        '10265' => q{New York},
        '10268' => q{New York},
        '10269' => q{New York},
        '10270' => q{New York},
        '10271' => q{New York},
        '10272' => q{New York},
        '10273' => q{New York},
        '10274' => q{New York},
        '10275' => q{New York},
        '10276' => q{New York},
        '10277' => q{New York},
        '10278' => q{New York},
        '10279' => q{New York},
        '10280' => q{New York},
        '10281' => q{New York},
        '10282' => q{New York},
        '10285' => q{New York},
        '10286' => q{New York},
        '10451' => q{Bronx},
        '10452' => q{Bronx},
        '10453' => q{Bronx},
        '10454' => q{Bronx},
        '10455' => q{Bronx},
        '10456' => q{Bronx},
        '10457' => q{Bronx},
        '10458' => q{Bronx},
        '10459' => q{Bronx},
        '10460' => q{Bronx},
        '10461' => q{Bronx},
        '10462' => q{Bronx},
        '10463' => q{Bronx},
        '10464' => q{Bronx},
        '10465' => q{Bronx},
        '10466' => q{Bronx},
        '10467' => q{Bronx},
        '10468' => q{Bronx},
        '10469' => q{Bronx},
        '10470' => q{Bronx},
        '10471' => q{Bronx},
        '10472' => q{Bronx},
        '10473' => q{Bronx},
        '10474' => q{Bronx},
        '10475' => q{Bronx},
        '11201' => q{Brooklyn},
        '11202' => q{Brooklyn},
        '11203' => q{Brooklyn},
        '11204' => q{Brooklyn},
        '11205' => q{Brooklyn},
        '11206' => q{Brooklyn},
        '11207' => q{Brooklyn},
        '11208' => q{Brooklyn},
        '11209' => q{Brooklyn},
        '11210' => q{Brooklyn},
        '11211' => q{Brooklyn},
        '11212' => q{Brooklyn},
        '11213' => q{Brooklyn},
        '11214' => q{Brooklyn},
        '11215' => q{Brooklyn},
        '11216' => q{Brooklyn},
        '11217' => q{Brooklyn},
        '11218' => q{Brooklyn},
        '11219' => q{Brooklyn},
        '11220' => q{Brooklyn},
        '11221' => q{Brooklyn},
        '11222' => q{Brooklyn},
        '11223' => q{Brooklyn},
        '11224' => q{Brooklyn},
        '11225' => q{Brooklyn},
        '11226' => q{Brooklyn},
        '11228' => q{Brooklyn},
        '11229' => q{Brooklyn},
        '11230' => q{Brooklyn},
        '11231' => q{Brooklyn},
        '11232' => q{Brooklyn},
        '11233' => q{Brooklyn},
        '11234' => q{Brooklyn},
        '11235' => q{Brooklyn},
        '11236' => q{Brooklyn},
        '11237' => q{Brooklyn},
        '11238' => q{Brooklyn},
        '11239' => q{Brooklyn},
        '11241' => q{Brooklyn},
        '11242' => q{Brooklyn},
        '11243' => q{Brooklyn},
        '11245' => q{Brooklyn},
        '11247' => q{Brooklyn},
        '11249' => q{Brooklyn},
        '11251' => q{Brooklyn},
        '11252' => q{Brooklyn},
        '11256' => q{Brooklyn},
        '10301' => q{Staten Island,Richmond},
        '10302' => q{Staten Island,Richmond},
        '10303' => q{Staten Island,Richmond},
        '10304' => q{Staten Island,Richmond},
        '10305' => q{Staten Island,Richmond},
        '10306' => q{Staten Island,Richmond},
        '10307' => q{Staten Island,Richmond},
        '10308' => q{Staten Island,Richmond},
        '10309' => q{Staten Island,Richmond},
        '10310' => q{Staten Island,Richmond},
        '10311' => q{Staten Island,Richmond},
        '10312' => q{Staten Island,Richmond},
        '10313' => q{Staten Island,Richmond},
        '10314' => q{Staten Island,Richmond},
        '11004' => q{Glen Oaks,Queens},
        '11005' => q{Floral Park,Queens},
        '11101' => q{Long Island City,Queens},
        '11102' => q{Astoria,Queens},
        '11103' => q{Astoria,Queens},
        '11104' => q{Sunnyside,Queens},
        '11105' => q{Astoria,Queens},
        '11106' => q{Astoria,Queens},
        '11109' => q{Long Island City,Queens},
        '11120' => q{Long Island City,Queens},
        '11351' => q{Flushing,Queens},
        '11352' => q{Flushing,Queens},
        '11354' => q{Flushing,Queens},
        '11355' => q{Flushing,Queens},
        '11356' => q{College Point,Queens},
        '11357' => q{Whitestone,Queens},
        '11358' => q{Flushing,Queens},
        '11359' => q{Bayside,Queens},
        '11360' => q{Bayside,Queens},
        '11361' => q{Bayside,Queens},
        '11362' => q{Little Neck,Queens},
        '11363' => q{Little Neck,Queens},
        '11364' => q{Oakland Gardens,Queens},
        '11365' => q{Fresh Meadows,Queens},
        '11366' => q{Fresh Meadows,Queens},
        '11367' => q{Flushing,Queens},
        '11368' => q{Corona,Queens},
        '11369' => q{East Elmhurst,Queens},
        '11370' => q{East Elmhurst,Queens},
        '11371' => q{Flushing,Queens},
        '11372' => q{Jackson Heights,Queens},
        '11373' => q{Elmhurst,Queens},
        '11374' => q{Rego Park,Queens},
        '11375' => q{Forest Hills,Queens},
        '11377' => q{Woodside,Queens},
        '11378' => q{Maspeth,Queens},
        '11379' => q{Middle Village,Queens},
        '11380' => q{Elmhurst,Queens},
        '11381' => q{Flushing,Queens},
        '11385' => q{Ridgewood,Queens},
        '11386' => q{Ridgewood,Queens},
        '11405' => q{Jamaica,Queens},
        '11411' => q{Cambria Heights,Queens},
        '11412' => q{Saint Albans,Queens},
        '11413' => q{Springfield Gardens,Queens},
        '11414' => q{Howard Beach,Queens},
        '11415' => q{Kew Gardens,Queens},
        '11416' => q{Ozone Park,Queens},
        '11417' => q{Ozone Park,Queens},
        '11418' => q{Richmond Hill,Queens},
        '11419' => q{South Richmond Hill,Queens},
        '11420' => q{South Ozone Park,Queens},
        '11421' => q{Woodhaven,Queens},
        '11422' => q{Rosedale,Queens},
        '11423' => q{Hollis,Queens},
        '11424' => q{Jamaica,Queens},
        '11425' => q{Jamaica,Queens},
        '11426' => q{Bellerose,Queens},
        '11427' => q{Queens Village,Queens},
        '11428' => q{Queens Village,Queens},
        '11429' => q{Queens Village,Queens},
        '11430' => q{Jamaica,Queens},
        '11431' => q{Jamaica,Queens},
        '11432' => q{Jamaica,Queens},
        '11433' => q{Jamaica,Queens},
        '11434' => q{Jamaica,Queens},
        '11435' => q{Jamaica,Queens},
        '11436' => q{Jamaica,Queens},
        '11437' => q{Jamaica,Queens},
        '11439' => q{Jamaica,Queens},
        '11451' => q{Jamaica,Queens},
        '11499' => q{Jamaica,Queens},
        '11690' => q{Far Rockaway,Queens},
        '11691' => q{Far Rockaway,Queens},
        '11692' => q{Arverne,Queens},
        '11693' => q{Far Rockaway,Queens},
        '11694' => q{Rockaway Park,Queens},
        '11695' => q{Far Rockaway,Queens},
        '11697' => q{Breezy Point,Queens},
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

# Fix for the first set of data which I missed.
sub _missed_testing_date {
    return [
        {
            zip          => 99999,
            positive     => 32,
            total_tested => 36,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10001,
            positive     => 113,
            total_tested => 265,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10002,
            positive     => 250,
            total_tested => 542,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10003,
            positive     => 161,
            total_tested => 379,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10004,
            positive     => 16,
            total_tested => 38,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10005,
            positive     => 25,
            total_tested => 81,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10006,
            positive     => 6,
            total_tested => 24,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10007,
            positive     => 26,
            total_tested => 67,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10009,
            positive     => 181,
            total_tested => 450,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10010,
            positive     => 101,
            total_tested => 282,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10011,
            positive     => 222,
            total_tested => 487,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10012,
            positive     => 68,
            total_tested => 183,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10013,
            positive     => 122,
            total_tested => 255,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10014,
            positive     => 140,
            total_tested => 305,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10016,
            positive     => 288,
            total_tested => 581,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10017,
            positive     => 45,
            total_tested => 138,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10018,
            positive     => 66,
            total_tested => 151,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10019,
            positive     => 187,
            total_tested => 451,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10021,
            positive     => 211,
            total_tested => 562,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10022,
            positive     => 123,
            total_tested => 339,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10023,
            positive     => 190,
            total_tested => 503,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10024,
            positive     => 204,
            total_tested => 641,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10025,
            positive     => 252,
            total_tested => 754,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10026,
            positive     => 126,
            total_tested => 300,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10027,
            positive     => 170,
            total_tested => 422,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10028,
            positive     => 189,
            total_tested => 476,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10029,
            positive     => 290,
            total_tested => 668,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10030,
            positive     => 106,
            total_tested => 204,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10031,
            positive     => 217,
            total_tested => 405,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10032,
            positive     => 308,
            total_tested => 548,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10033,
            positive     => 264,
            total_tested => 495,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10034,
            positive     => 108,
            total_tested => 262,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10035,
            positive     => 147,
            total_tested => 345,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10036,
            positive     => 116,
            total_tested => 275,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10037,
            positive     => 109,
            total_tested => 204,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10038,
            positive     => 76,
            total_tested => 167,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10039,
            positive     => 116,
            total_tested => 226,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10040,
            positive     => 208,
            total_tested => 356,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10044,
            positive     => 49,
            total_tested => 116,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10065,
            positive     => 121,
            total_tested => 385,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10069,
            positive     => 24,
            total_tested => 57,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10075,
            positive     => 160,
            total_tested => 371,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10128,
            positive     => 212,
            total_tested => 596,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10280,
            positive     => 17,
            total_tested => 50,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10282,
            positive     => 21,
            total_tested => 42,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10301,
            positive     => 175,
            total_tested => 333,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10302,
            positive     => 61,
            total_tested => 137,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10303,
            positive     => 106,
            total_tested => 221,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10304,
            positive     => 289,
            total_tested => 540,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10305,
            positive     => 178,
            total_tested => 428,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10306,
            positive     => 278,
            total_tested => 632,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10307,
            positive     => 67,
            total_tested => 142,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10308,
            positive     => 146,
            total_tested => 331,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10309,
            positive     => 170,
            total_tested => 363,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10310,
            positive     => 97,
            total_tested => 218,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10312,
            positive     => 336,
            total_tested => 654,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10314,
            positive     => 452,
            total_tested => 959,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10451,
            positive     => 337,
            total_tested => 585,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10452,
            positive     => 367,
            total_tested => 629,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10453,
            positive     => 386,
            total_tested => 663,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10454,
            positive     => 174,
            total_tested => 343,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10455,
            positive     => 176,
            total_tested => 351,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10456,
            positive     => 355,
            total_tested => 693,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10457,
            positive     => 306,
            total_tested => 571,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10458,
            positive     => 332,
            total_tested => 622,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10459,
            positive     => 227,
            total_tested => 423,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10460,
            positive     => 255,
            total_tested => 484,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10461,
            positive     => 376,
            total_tested => 714,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10462,
            positive     => 377,
            total_tested => 768,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10463,
            positive     => 253,
            total_tested => 654,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10464,
            positive     => 25,
            total_tested => 65,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10465,
            positive     => 267,
            total_tested => 596,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10466,
            positive     => 362,
            total_tested => 666,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10467,
            positive     => 638,
            total_tested => 1134,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10468,
            positive     => 397,
            total_tested => 624,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10469,
            positive     => 470,
            total_tested => 815,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10470,
            positive     => 83,
            total_tested => 157,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10471,
            positive     => 104,
            total_tested => 297,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10472,
            positive     => 302,
            total_tested => 528,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10473,
            positive     => 304,
            total_tested => 556,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10474,
            positive     => 55,
            total_tested => 97,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 10475,
            positive     => 255,
            total_tested => 446,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11429,
            positive     => 163,
            total_tested => 265,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11004,
            positive     => 121,
            total_tested => 204,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11101,
            positive     => 148,
            total_tested => 320,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11102,
            positive     => 105,
            total_tested => 231,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11103,
            positive     => 104,
            total_tested => 203,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11104,
            positive     => 85,
            total_tested => 155,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11105,
            positive     => 104,
            total_tested => 242,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11106,
            positive     => 144,
            total_tested => 290,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11109,
            positive     => 13,
            total_tested => 45,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11201,
            positive     => 204,
            total_tested => 479,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11203,
            positive     => 343,
            total_tested => 546,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11204,
            positive     => 534,
            total_tested => 932,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11205,
            positive     => 182,
            total_tested => 319,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11206,
            positive     => 329,
            total_tested => 572,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11207,
            positive     => 332,
            total_tested => 587,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11208,
            positive     => 350,
            total_tested => 561,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11209,
            positive     => 209,
            total_tested => 452,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11210,
            positive     => 386,
            total_tested => 671,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11211,
            positive     => 601,
            total_tested => 961,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11212,
            positive     => 254,
            total_tested => 445,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11213,
            positive     => 394,
            total_tested => 621,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11214,
            positive     => 251,
            total_tested => 544,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11215,
            positive     => 178,
            total_tested => 437,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11216,
            positive     => 162,
            total_tested => 316,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11217,
            positive     => 130,
            total_tested => 269,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11218,
            positive     => 350,
            total_tested => 613,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11219,
            positive     => 771,
            total_tested => 1146,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11220,
            positive     => 264,
            total_tested => 459,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11221,
            positive     => 260,
            total_tested => 455,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11222,
            positive     => 96,
            total_tested => 236,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11223,
            positive     => 346,
            total_tested => 642,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11224,
            positive     => 133,
            total_tested => 304,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11225,
            positive     => 267,
            total_tested => 427,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11226,
            positive     => 344,
            total_tested => 600,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11228,
            positive     => 101,
            total_tested => 222,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11229,
            positive     => 316,
            total_tested => 640,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11230,
            positive     => 631,
            total_tested => 1046,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11231,
            positive     => 127,
            total_tested => 271,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11232,
            positive     => 85,
            total_tested => 150,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11233,
            positive     => 225,
            total_tested => 383,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11234,
            positive     => 364,
            total_tested => 713,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11235,
            positive     => 348,
            total_tested => 684,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11236,
            positive     => 416,
            total_tested => 701,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11237,
            positive     => 184,
            total_tested => 288,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11238,
            positive     => 183,
            total_tested => 350,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11239,
            positive     => 85,
            total_tested => 129,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11357,
            positive     => 162,
            total_tested => 320,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11354,
            positive     => 134,
            total_tested => 272,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11355,
            positive     => 213,
            total_tested => 364,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11356,
            positive     => 110,
            total_tested => 226,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11358,
            positive     => 119,
            total_tested => 248,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11360,
            positive     => 59,
            total_tested => 153,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11361,
            positive     => 85,
            total_tested => 188,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11362,
            positive     => 64,
            total_tested => 143,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11363,
            positive     => 27,
            total_tested => 65,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11364,
            positive     => 113,
            total_tested => 220,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11365,
            positive     => 166,
            total_tested => 312,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11366,
            positive     => 106,
            total_tested => 183,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11367,
            positive     => 318,
            total_tested => 511,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11368,
            positive     => 947,
            total_tested => 1227,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11369,
            positive     => 331,
            total_tested => 454,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11370,
            positive     => 378,
            total_tested => 777,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11372,
            positive     => 492,
            total_tested => 693,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11373,
            positive     => 831,
            total_tested => 1148,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11374,
            positive     => 319,
            total_tested => 535,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11375,
            positive     => 418,
            total_tested => 838,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11377,
            positive     => 364,
            total_tested => 628,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11378,
            positive     => 156,
            total_tested => 285,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11379,
            positive     => 195,
            total_tested => 360,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11385,
            positive     => 425,
            total_tested => 759,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11411,
            positive     => 151,
            total_tested => 221,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11412,
            positive     => 245,
            total_tested => 410,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11413,
            positive     => 261,
            total_tested => 432,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11414,
            positive     => 162,
            total_tested => 321,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11415,
            positive     => 149,
            total_tested => 243,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11416,
            positive     => 117,
            total_tested => 185,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11417,
            positive     => 173,
            total_tested => 291,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11418,
            positive     => 216,
            total_tested => 363,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11419,
            positive     => 182,
            total_tested => 334,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11420,
            positive     => 223,
            total_tested => 390,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11421,
            positive     => 202,
            total_tested => 352,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11422,
            positive     => 211,
            total_tested => 341,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11423,
            positive     => 164,
            total_tested => 270,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11426,
            positive     => 101,
            total_tested => 202,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11427,
            positive     => 181,
            total_tested => 323,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11428,
            positive     => 112,
            total_tested => 171,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11434,
            positive     => 358,
            total_tested => 555,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11432,
            positive     => 405,
            total_tested => 613,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11433,
            positive     => 155,
            total_tested => 250,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11435,
            positive     => 293,
            total_tested => 517,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11436,
            positive     => 100,
            total_tested => 155,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11691,
            positive     => 436,
            total_tested => 694,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11692,
            positive     => 110,
            total_tested => 184,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11693,
            positive     => 86,
            total_tested => 144,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11694,
            positive     => 143,
            total_tested => 270,
            yyyymmdd     => '20200401'
        },
        {
            zip          => 11697,
            positive     => 25,
            total_tested => 62,
            yyyymmdd     => '20200401'
        },
    ];
}

#-------------------------------------------------------------------------------
#  END
#-------------------------------------------------------------------------------
1;
