# covid
Some scripts for analyzing New York City Covid-19 AKA the Trump virus. 

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

```shell
perl bin\city_covid_data.pl --show_zip_stats 11368,10467,11373,11219
```
Will display the NYC testing statistics for the four zip codes, 11368,10467,11373,11219, using Chart::Plotly, Perls interface to the Plotly charting library.
<!DOCTYPE html>
<head>
<meta charset="utf-8" />
</head>
<body>
<div id="dfeba44e-81c9-11ea-9b6c-ba97480773c8"></div>
<script src="https://cdn.plot.ly/plotly-1.52.2.min.js"></script>
<script>
Plotly.react(document.getElementById('dfeba44e-81c9-11ea-9b6c-ba97480773c8'),[{"y":["947","1245","1337","1446","1659","1728","2132","2248","2287","2398","2446","2510","2563","2631","2701","2701"],"name":"Corona, West Queens","text":"11368","type":"bar","x":["2020-04-03","2020-04-04","2020-04-05","2020-04-06","2020-04-07","2020-04-08","2020-04-09","2020-04-10","2020-04-11","2020-04-12","2020-04-13","2020-04-14","2020-04-15","2020-04-16","2020-04-17","2020-04-18"]},{"y":["638","836","889","941","1142","1209","1442","1626","1653","1769","1818","1918","1972","2087","2154","2154"],"name":"Bronx Park and Fordham, Bronx","x":["2020-04-03","2020-04-04","2020-04-05","2020-04-06","2020-04-07","2020-04-08","2020-04-09","2020-04-10","2020-04-11","2020-04-12","2020-04-13","2020-04-14","2020-04-15","2020-04-16","2020-04-17","2020-04-18"],"type":"bar","text":"10467"},{"name":"Elmhurst, West Queens","y":["831","841","903","983","1142","1190","1602","1737","1779","1859","1893","1939","1978","2031","2104","2104"],"x":["2020-04-03","2020-04-04","2020-04-05","2020-04-06","2020-04-07","2020-04-08","2020-04-09","2020-04-10","2020-04-11","2020-04-12","2020-04-13","2020-04-14","2020-04-15","2020-04-16","2020-04-17","2020-04-18"],"type":"bar","text":"11373"},{"x":["2020-04-03","2020-04-04","2020-04-05","2020-04-06","2020-04-07","2020-04-08","2020-04-09","2020-04-10","2020-04-11","2020-04-12","2020-04-13","2020-04-14","2020-04-15","2020-04-16","2020-04-17","2020-04-18"],"type":"bar","text":"11219","y":["771","1037","1088","1136","1314","1417","1513","1562","1564","1679","1698","1725","1833","1868","1914","1914"],"name":"Borough Park, Brooklyn"}] ,{"barmode":"group"} );
</script>
</body>
</html>
