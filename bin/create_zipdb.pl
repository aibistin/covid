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
use Path::Tiny qw/path/;
use Data::Dump qw/dump/;
use Types::Path::Tiny qw/Path AbsPath/;
use File::Serialize qw/serialize_file deserialize_file/;
use FindBin qw/$Bin/;

#-------------------------------------------------------------------------------
# Options
#-------------------------------------------------------------------------------
option create_zip_db => (
    is    => 'ro',
    short => 'new_zipdb|new_zip',
    doc   => q/Create a new NYC Zip, Borough, District, Town JSON file./,
);

option read_zip_db => (
    is    => 'ro',
    short => 'read_db',
    doc   => q/Read the NYC Zip file database./,
);

option verbose => ( is => 'ro', doc => 'Print details' );

#-------------------------------------------------------------------------------
# Attributes
#-------------------------------------------------------------------------------
has db_dir => (
    is      => 'rw',
    isa     => Path,
    coerce  => 1,
    default => sub { "$Bin/../db" }
);

# Database file
has zip_db_json_file => (
    is      => 'lazy',
    isa     => Path,
    builder => sub {
        $_[0]->db_dir->child("zip_db.json");
    }
);

# Database data structure
has zip_hash => (
    is => 'lazy',
    isa =>
      sub { die "'zips_hash' must be a HASH" unless ( ref( $_[0] ) eq 'HASH' ) }
    ,
    builder => sub {
        deserialize_file $_[0]->zip_db_json_file;
    }
);

#===============================================================================
# Main
#===============================================================================
sub run {
    my ($self) = @_;
    $self->create_new_zipdb_file if $self->create_zip_db;
    $self->read_and_dump_the_db  if $self->read_zip_db;
    say "All Done!"              if $self->verbose;
}

main->new_with_options()->run;

#===============================================================================
# Methods
#===============================================================================

sub create_new_zipdb_file {
    my $self          = shift;
    my $zip_boro_dist = $self->get_raw_zip_data();
    serialize_file $self->zip_db_json_file => $zip_boro_dist;
    say "Created a new " . $self->zip_db_json_file if $self->verbose;
}

sub get_raw_zip_data {
    my $self         = shift;
    my %zips_to_city = %{ _get_zips_to_city() };
    my %bdz          = %{ _get_borough_district_zips() };
    my %zip_boro_dist;
    for my $borough ( sort keys %bdz ) {
        my %district = %{ $bdz{$borough} };
        for my $district_name ( sort keys %district ) {
            my @district_zips = @{ $district{$district_name} };
            for my $zip ( sort @district_zips ) {
                my ( $city, $county ) = split /,/, $zips_to_city{$zip};
                $county =
                    $borough eq 'Brooklyn' ? 'Kings'
                  : $borough eq 'Bronx'    ? 'Bronx'
                  : 'New York'
                  unless $county;

                $zip_boro_dist{$zip} = {
                    borough  => $borough,
                    district => $district_name,
                    city     => $city,
                    county   => $county,
                };
            }
        }
    }
    return \%zip_boro_dist;
}

sub read_and_dump_the_db {
    my $self         = shift;
    my $location_rec = $self->zip_hash;
    dump $location_rec;
}

#-------------------------------------------------------------------------------
#   Input Zip Structures
#-------------------------------------------------------------------------------

# Zip info from:
# https://www.health.ny.gov/statistics/cancer/registry/appendix/neighborhoods.htm
# Added: 10069 => "Upper West Side"
#        10280 10282 => "Battery Park City" => Lower Manhattan
#        11109 =>  "Long Island City, Queens" => The new development around Gantry Park
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
            'Greenwich Village, Chinatown, Little Italy' => [qw/10013/]
            ,    # My addition
            'Lower Manhattan' => [qw/10004 10005 10006 10007 10038/],
            'Lower East Side' => [qw/10003 10009/],
            'Lower East Side, Chinatown' => [qw/10002/],    # My addition
            'Lower East Side, Battery Park City' => [qw/10280 10282/]
            ,                                               # My addition
            'Upper East Side' => [qw/10021 10028 10044 10065 10075 10128/],
            'Upper West Side' => [qw/10023 10024 10025 10069/],
            'Inwood and Washington Heights' =>
              [qw/10031 10032 10033 10034 10040/],
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

# Not sure where I got this from.
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
        '10212' => q{New York},
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
#  END
#-------------------------------------------------------------------------------
1;
