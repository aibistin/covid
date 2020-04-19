# covid
### Some scripts for analyzing New York City Covid-19 test results. 

```shell
USAGE: city_covid_data.pl [-h] [long options ...]

    -n --create_new_zcta_db     Create a new NYC Zip Cumulative Test 'A'
                                JSON db for todays result
    --show_zip_stats=[Strings]  Get the available statistics of a given zip
                                code or codes
    -v --verbose                Print details
    -c --write_zcta_to_csv      Print latest ZCTA data to csv, 'output/
                                all_zcta_data.csv'

    --usage                     show a short help message
    -h                          show a compact help message
    --help                      show a long help message
    --man                       show the manual
```

### To Display On A HTML Plotly Chart
```shell
perl bin\city_covid_data.pl --show_zip_stats 11368,10467,11373,11219

This will display the positive test results for the zip codes, 11368,10467,11373,11219, on a HTML file usint the Plotly JavaScript charting library. 

### For more details you can also read [my blog](http://www.aibistin.com/?p=727)