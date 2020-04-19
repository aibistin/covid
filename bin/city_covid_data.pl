#!/usr/bin/env perl
#===============================================================================
#
#         FILE: city_covid_data.pl
#
#        USAGE: ./city_covid_data.pl
#
#  DESCRIPTION:
#
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
use Types::Path::Tiny qw/Path/;
use File::Serialize qw/serialize_file deserialize_file/;
use Time::Piece;
use Chart::Plotly;
use Chart::Plotly::Trace::Bar;
use Chart::Plotly::Plot;
# use HTML::Show;
use LWP::Simple qw/get/;
use Text::CSV_XS;
use FindBin qw/$Bin/;

use lib "$Bin/../lib";
use ZipDb;

#-------------------------------------------------------------------------------
#  Constants
#-------------------------------------------------------------------------------
my $RAW_ZCTA_DATA_LINK =
q{https://raw.githubusercontent.com/nychealth/coronavirus-data/master/tests-by-zcta.csv};
my $NA_ZIP            = '88888';
my $ALL_ZCTA_DATA_CSV = 'all_zcta_data.csv';
my $DB_DIR            = "$Bin/../db";
my $VIEW_NAME         = q/all_zcta_view/;
my $THIS_SCRIPT       = path($0)->basename;

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

option show_zip_stats => (
    is        => 'ro',
    format    => 's@',
    autosplit => ',',
    default   => sub { [] },
    short     => 'zip_stats',
    doc       => q/Get the available statistics of a given zip code or codes/,
    long_doc  => qq{
        Get the available statistics of a given zip code
        $THIS_SCRIPT --zip_stats 11379,11104
        # Will create a HTML Chart
    },
);

option verbose => (
    is    => 'ro',
    doc   => 'Print details',
    short => 'v',
);

#-------------------------------------------------------------------------------
# Attributes
#-------------------------------------------------------------------------------
has db_dir => (
    is      => 'ro',
    isa     => Path,
    coerce  => 1,
    default => $DB_DIR,
);

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

has zip_db => (
    is => 'lazy',
    isa =>
      sub { die "'zip_db' must be a ZipDb" unless ( ref( $_[0] ) eq 'ZipDb' ) },
    builder => sub {
        return ZipDb->new( db_dir => $_[0]->db_dir );
    }
);

has date_to_str_func => (
    is  => 'lazy',
    isa => sub {
        die "'date_to_str_func' must be a SUB"
          unless ( ref( $_[0] ) eq 'CODE' );
    },
    builder => sub {
        my %cache;
        $cache{20200401} = '2020-04-03';    # Fudge as data from Apr 1 to 3
        return sub {
            my $date = shift;
            return $cache{$date} if $cache{$date};
            my ( $y, $m, $d ) = ( $date =~ /(\d{4})(\d{2})(\d{2})/ );
            return $cache{$date} = "$y-$m-$d";
        };
    },
);

#===============================================================================
# Main
#===============================================================================
sub run {
    my ($self) = @_;

    $self->create_latest_tests_by_ztca_file if $self->create_new_zcta_db;
    $self->create_zcta_view                 if $self->create_new_zcta_db;

    $self->write_latest_zcta_to_csv if $self->write_zcta_to_csv;
    $self->show_stats_for_zips( $self->show_zip_stats )
      if ( @{ $self->show_zip_stats } );

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
        my $location_rec =
          $self->zip_db->zip_db_hash->{ $one_day_zip_rec->{zip} }
          || _get_filler_location_rec( $one_day_zip_rec->{zip} );
        $self->zip_db->zip_db_hash->{ $one_day_zip_rec->{zip} } ||=
          $location_rec;
        my %csv_rec = ( %$one_day_zip_rec, %$location_rec );
        $csv->print( $z_fh, [ @csv_rec{@col_names} ] );
    }
    close($z_fh) or warn "Failed to close $zcta_file";
    say "Created a new $zcta_file";
}

sub create_zcta_view {
    my $self = shift;
    my $ct;
    my @view;
    for my $one_day_tests ( @{ $self->all_tests_by_zcta_data } ) {
        my %day_view;
        for my $test_rec ( sort { $a->{zip} <=> $b->{zip} } @{$one_day_tests} )
        {
            my $location_rec = $self->zip_db->zip_db_hash->{ $test_rec->{zip} }
              || _get_filler_location_rec( $test_rec->{zip} );
            $self->zip_db->zip_db_hash->{ $test_rec->{zip} } ||= $location_rec;
            $day_view{ $test_rec->{zip} } = { %$test_rec, %$location_rec };
        }
        push @view, \%day_view;
    }
    my $view_file = $self->get_view_file($VIEW_NAME);
    serialize_file $view_file => \@view;
    say "Created a new $view_file";

    # `notepad++ "$view_file"`;
}

sub get_view_file {
    my ( $self, $view_file_name ) = @_;
    state $views_dir = $self->db_dir->child('views');
    $views_dir->mkpath unless ( -d $views_dir );
    my $view_file = $views_dir->child( $view_file_name . '.json' );
    $view_file->mkpath unless ( -f $view_file );
    return $view_file;
}

sub read_view {
    my $self      = shift;
    my $view_file = $self->get_view_file($VIEW_NAME);
    deserialize_file $view_file;
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

sub show_stats_for_zips {
    my ( $self, $zip_codes ) = @_;
    my $max_zip = '11368';    # Corona
    Carp::confess "'show_stats_for_zips' requires some zip codes!" unless ( defined $zip_codes );

    my @chart_names = ref($zip_codes) eq 'ARRAY' ? @{$zip_codes} : ($zip_codes);
    my $date_conv_func   = $self->date_to_str_func();
    my $stats_cache_func = _get_zip_chart_stats_cache_func();

    my @charts;
    for my $zip_code (@chart_names) {
        my $zip_code_stats = $stats_cache_func->( $self, $zip_code );
        my $chart = Chart::Plotly::Trace::Bar->new(
            x => [
                map { $date_conv_func->($_) }
                  @{ $zip_code_stats->{dates} || [] }
            ],
            y => [ @{ $zip_code_stats->{positive} || [] } ],
            name => $self->city_district($zip_code),
            text => $zip_code,
            # text => [ @{ $zip_code_stats->{positive} || [] } ],
            # textposition => 'inside',
        );
        push @charts, $chart;
    }

    # say "STATS: " . ( dump \@positive_stats );

    say "BARS: " . ( dump \@charts );

    my $bar_chart = Chart::Plotly::Plot->new(
        traces => [@charts],
        layout => { barmode => 'group' }
    );

    Chart::Plotly::show_plot($bar_chart);
}

sub city_district {
    my ( $self, $zip_code ) = @_;
    my $borough = $self->zip_db->zip_db_hash->{$zip_code}{borough};
    my $city    = $self->zip_db->zip_db_hash->{$zip_code}{city};
    return $city . ', ' . $self->zip_db->zip_db_hash->{$zip_code}{district} if ( $borough eq 'Queens' );
    $city = 'Manhattan' if ( $city eq 'New York' );
    return $self->zip_db->zip_db_hash->{$zip_code}{district} . ', ' . $city;
}

sub get_zip_details {
    my ( $self, $zip_codes ) = @_;
    Carp::confess "'get_zip_details' requires some zip codes!"
      unless ( defined $zip_codes );
    my @zip_codes = ref($zip_codes) eq 'ARRAY' ? @{$zip_codes} : ($zip_codes);
    my @details;
    for my $zip (@zip_codes) {
        ( $zip !~ /\A\d{5}\z/ ) && do {
            warn "Zip, <$zip> looks invalid!";
            next;
        };
        push @details, { $zip => $self->zip_db_hash->{$zip} }
          if $self->zip_db_hash->{$zip};
    }
    return \@details;
}

sub _get_zip_chart_stats_cache_func {
    my %zip_stat_cache;

    return sub {
        my ( $self, $the_zip ) = @_;
        return $zip_stat_cache{$the_zip} if $zip_stat_cache{$the_zip};
        my $zip_all_stats = $self->get_stats_for_zip($the_zip);
        $zip_stat_cache{$the_zip}{all_stats} = $zip_all_stats;

        for my $stat ( sort { $a->{yyyymmdd} <=> $b->{yyyymmdd} }
            @{$zip_all_stats} )
        {
            push @{ $zip_stat_cache{$the_zip}{dates} },    $stat->{yyyymmdd};
            push @{ $zip_stat_cache{$the_zip}{positive} }, $stat->{positive};
            push @{ $zip_stat_cache{$the_zip}{total_tested} },
              $stat->{total_tested};
            push
              @{ $zip_stat_cache{$the_zip}{cumulative_percent_of_those_tested}
              },
              $stat->{cumulative_percent_of_those_tested} || 0;
        }
        return $zip_stat_cache{$the_zip};
    };
}

sub get_stats_for_zip {
    my ( $self, $the_zip ) = @_;
    my @zip_stats;
    for my $one_day_rec ( @{ $self->read_view } ) {
        for my $zip ( keys %{$one_day_rec} ) {
            next unless ( $zip eq $the_zip );
            push @zip_stats, $one_day_rec->{$zip};
            last;
        }
    }
    return \@zip_stats;
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
