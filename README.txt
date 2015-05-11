#    Copyright 2015 Naddmr, http://www.forexfactory.com
#
#    This file is part of the mt4psql project.
#
#    mt4psql is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt4psql is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with mt4psql.  If not, see <http://www.gnu.org/licenses/>.
#
#
[B][U]Introductionary words:[/U][/B]
 
This Lazarus-project creates a DLL named mt4psql.dll which is capable to connect Metatrader 4.5 to a PostgreSQL 9.x database to export tickdata to PostgreSQL. The DLL is able to export tick data from different machines connected to different brokers into one single database so that you can compare the tick data from different brokers directly.
 
You can also connect to the PostgreSQL database using [R] and import tick data into [R] to compute some really nice statistics on them.
 
In this way you're able to get a well founded research why some EAs do not work on all brokers.
Or you might want to prove in a dispute that the broker sent a bad tick to your MT4 installation which means a tick with a timestamp more in the past than the tick received before. This should not happen - but well ... :-)
 
In this example I had the export API running on three different VPS machines connected to FXCM REAL (1), FXCM DEMO (3) and OANDA REAL (2).
[attach]1670747[/attach]
 
You can clearly see that OANDA delivers only a half of the number of ticks per minute to MT4 and that the FXCM DEMO does not receive as many ticks per minute than FXCM LIVE.
 
Your mileage may vary of course.
 
As MetaQuotes does not provide a more fine granulated timestamp than a second the local time of the instance running the export DLL is also stored into the tick data. You can use this to calculate a rough estimation how long a tick does take from the broker to your MT4 installation on your VPS.
 
You can also prove by using mt4psql.dll, that some brokers make you trade in the past, which makes them pretty vulnerable to some really nice time arbitrage trading.
 

[U][B]On the datastructure in the database:[/B][/U]
 
All tables and their columns are documented.

You can use PGADMIN III to view those comments if you're into graphic interfaces.

Or you can use the "\d+" command in psql to do that if you're more into command line interfaces:

Example:
Open up your "psql" PostgreSQL command line interface and type
[code]
\d+ t_mt4_brokers
[/code]

This command will give you the structure of the table "t_mt4_brokers" and a description of the columns in that table.


The tables relate to each other using an ID. 
The column "broker_id" contains the same value in t_mt4_brokers as in t_mt4_pairdata.
If a broker_id of a table is the same as the broker_id in another table it is the same broker which is referenced by that.
Trivial, eh?

 
[U]PAIR-BROKER[/U]
One Broker (t_mt4_brokers) has one or more pairs (t_mt4_pairdata)
One pair (t_mt4_pairdata) has belongs to exactly one broker (t_mt4_brokers)
So the "t_mt4_pairdata" has a column "broker_id" which references its broker.
This relation type is called 1:n(1) (One to many).
 

[U]PAIR-ALIAS[/U]
One Alias (t_mt4_aliasnames) defines one or more pairs (t_mt4_pairdata)
One pair (t_mt4_pairdata) has at least one alias name (t_mt4_aliasnames).
Pairs and alias names relate on a binding table (t_mt4_pairaliases) together.
This relation type is called n:m (Many to many)

 
[U]PAIR-TICKS[/U]
One pair (t_mt4_pairdata) has zero or more ticks (t_mt4_ticks).
One tick (t_mt4_ticks) belongs to exactly one pair (t_mt4_pairdata).
This is also a 1:n relationship.


 
Example #1 for the use of aliasnames:
Use DAX as an alias name for GER30, GRX, DE30EUR etc.
1.) Create a new alias row:
[code]
insert into t_mt4_aliasnames (pairname) values ('DAX');
[/code]
 
2.) Get the alias id:
[code]
select * from t_mt4_aliasnames where pairname='DAX'
[/code]
 
3.) Let all pairs point to the new alias name via its value
in NEW_ALIAS_ID gotten in step 2):
[code]
-- Begin a new transaction - better safe than sorry...
begin transaction;
 
-- update all pairs
update t_mt4_pairaliases
	set alias_id=<NEW_ALIAS_ID>
where pair_id in (
	select pair_id from t_mt4_pairdata where pairname in ('GER30', 'GRX', 'DE30EUR')
);
 
-- check the modification
select
	*
from
	t_mt4_pairaliases
where
	pair_id in (
		select pair_id from t_mt4_pairdata where pairname in ('GER30', 'GRX', 'DE30EUR')
	);
 
-- if you made an error then issue
rollback;
 
-- if all went fine then uncomment this and comment out the "rollback" above.
-- commit;
 
Example #2 based on Example #1
To get all ticks from all DAX pairs from all brokers in the time
range 09:15 to 09:16 you would query:
select
	*
from (
	select
	substring(b.brokername, 1, 5) as brokername,
	b.is_demo,
	p.pairname,
	a.pairname as aliasname,
	t.*
from
	t_mt4_pairdata p
	join t_mt4_pairaliases pa using (pair_id)
	join t_mt4_aliasnames a using (alias_id)
	join t_mt4_brokers b using (broker_id)
	join t_mt4_ticks t using (pair_id)
) i
where
	i.aliasname='DAX' and
	i.loctimestamp>='2015-05-07 09:15:00'::timestamp and
	i.loctimestamp<'2015-05-07 09:16:00'::timestamp
	order by
	i.loctimestamp,
	i.ttimestamp,
	i.brokername
[/code]


[U][B]Some notes on the inner workings of the DLL:[/B][/U]
 
As a tick might get lost when the "int start()" function of MT4 is still working on a tick when a new tick arrives the received tick is put into a queue which is completely held in memory. In this way the DLL function is a simple dispatcher which does not consume any measurable time in the start() function of MT4.

A worker thread running asynchronously in the background parallel to the dispatcher is consuming the tick data from the dispatcher queue and is writing the tick data to SQL.

This worker thread DOES need some CPU power and might negatively impact the workings of your EAs if you export a lot of pairs on your VPS.
The next thing are comparable timestamps. This is achieved by recalculating the tick timestamp according to the broker time zone to a time stamp representing the time zone the database runs in.

Because of that it is crucial that you specify the right time zone of your broker in your configuration (see below).

There is no other need to maintain base tables like broker, pair or alias names. Each time a new name or a new broker or a new pair is detected it will be created in the database automatically and the structures to bind the data together is maintained by the DLL.

PostgreSQL does have mechanisms to enforce the validity of the relations and the data structures of this project make use of them.
 

[U][B]Caveats[/B][/U]
 
To avoid any performance impacts it is advisable that you export from a VPS which is dedicated to data exporting and not to trading.
It is also advisable that the PostgreSQL server runs on a different machine than the VPS - except you got plenty of CPU cores ;-)
And third: Do not change the timeframes of exporting charts after you started the export on it. You will lose some ticks during the initialization phase.

Also take your time to think of a database maintenance concept. 
You'll need a backup and recovery strategy for the database and you need to think about archiving the data.

I'm exporting from three brokers on 10 pairs and my database grows at a rate of ~ 700..800 MB a day.
 
 
[B][U]Three main steps to get things running:[/U][/B]
 
1.) Install a PostgreSQL server
It provides all DLLs neccessary for mt4psql.dll to
connect to a Postgresql database. If you do not
install the Postgres-Server, then mt4psql.dll won't
be running and the error message "cannot find lippg.dll"
will occur.
Why? Don't know.
1.1) Obtain a PostgreSQL-Installer here
[URL]http://www.postgresql.org/download/windows/[/URL]
The PostgreSQL installer for windows already contains the most
current version on PGADMIN III which is also strongly recommended.
 
1.2) Install it into a Directory different from "Program Files" e.g. "C:\Apps\Postgres"
1.3) Add the Postgresql directory to your search path in windows
so that the DLLs can be found.
1.4) If you already have a Postgresql machine running
turn the service off and set the service properties to "deactivated".
 
2.) Create a database and the neccessary structures on your PostgreSQL server
2.1) Create the database using the command:
psql -d template1 -U postgres -c "create database mtforex"
2.2) Create the tables in your newly created database using the command:
psql -d mtforex -U postgres -i "create_table.sql"
2.3) Check whether the all is fine and dandy using the command:
psql -d mtforex -U postgres -c "\d"
 
The expected output is:
[code]
                           List of relations
     Schema |                  Name                  |   Type   |  Owner  
    --------+----------------------------------------+----------+----------
     public | t_mt4_aliasnames                       | table    | postgres
     public | t_mt4_aliasnames_alias_id_seq          | sequence | postgres
     public | t_mt4_brokers                          | table    | postgres
     public | t_mt4_brokers_broker_id_seq            | sequence | postgres
     public | t_mt4_ohlc                             | table    | postgres
     public | t_mt4_pair_timeframes                  | table    | postgres
     public | t_mt4_pair_timeframes_timeframe_id_seq | sequence | postgres
     public | t_mt4_pairaliases                      | table    | postgres
     public | t_mt4_pairdata                         | table    | postgres
     public | t_mt4_pairdata_pair_id_seq             | sequence | postgres
     public | t_mt4_ticks                            | table    | postgres
    (11 rows)
[/code]
3.) Install the Indicator and the DLL to MT4
3.1) Stop MT4
3.2) Copy the mt4psql.dll to MQL4\Libraries
3.3) Copy the PQ_Writer.mq4 to MQL4\Indicators
3.4) Create a copy of the settings file "MQL4/Files/PQWriter_DB_Config_FXCM.set
3.5) Adapt the settings in your PQWriter_DB_Config_*.set to your installation:
[code]
    # Time zone of your broker as gotten by
    # select * from pg_timezones;
    BrokerTimezone=UTC
    # IP address of your PostgreSQL database server
    DBHostName=192.168.186.199
    # Port number of your PostgreSQL database server
    DBPortnumber=5432
    # Database name of your PostgreSQL database server
    DBDatabaseName=mtforex
    # Username to connect to your PostgreSQL database server
    DBUserName=postgres
    # Password to connect to your PostgreSQL database server
    DBPassword=
    # Number of retries to write a tick in case of an error
    DBMaxRetries=100
    # Milliseconds to poll the tick queue
    PollingInterval=500
[/code]
3.6) Start your MT4 and start a DBGVIEW window.
If you haven't installed it already, then you should do so
by downloading it here:
[URL]https://technet.microsoft.com/en-us/library/bb896647.aspx[/URL]
Without DBGVIEW you won't be able to see any error messages as
all relevant logging goes to the Windows Debuglog.
3.7) Drop the PQ_Writer indicator on your chart and enter the
name of your PQWriter_DB_Config_*.set file
You should see a log output in the expert log window like that:
[attach]1670739[/attach]
 
If there isn't any output then the .set file is missing from
MQL4\Files and step 3.4 has to be corrected.
If the export is running then a text "SQL-Export" is displayed on that
chart so you do not accidentially close the chart.
 
3.8) Check whether the output in the DBGVIEW looks like that:
[attach]1670737[/attach]
 
 
3.9) Check the data in the database by entering:
[code]
    psql -d mtforex -U postgres -c "select * from t_mt4_ticks where pair_id=40"
[/code]
"40" is the pair_id from my database - get your pair_id from the log output in
step 3.8
[code]
        WriterClass.getPairData GER30: Fetched pair_id=40 for pair/broker_id("GER30", 3)
[/code]
 
4.0) Populate all charts you want to export from using steps 3.7 to 3.9
 
[U][B]Database Maintenance[/B][/U]
 
After a while you might notice a slowdown and an increased CPU usage.
This is due to the fact that it is quite a bit of data which gets stored into the PostgreSQL server.
A typical export creates about 70 MB per broker per day per pair of data.
Some pairs like the EURAUD are pretty hoggy as far as ticks are concerned.
While PostgreSQL is designed for big data it is advisable that you export and archive your tick data off-database for to get the load off your
exporting VPS.
If you want to build a data ware house (DWH) from the data collected, you might want to import the tick table into a staging area of your DWH and delete the data from the export database after importing it.
One example for linux boxes is attached in the zip file.
The script is called "arch-data.sh" and is a simple bash script which exports data from the t_mt4_ticks table for each pair and each export into a separate 7z compressed archive file.
To run this script you should have postgresql-client and pk7zip-full installed on your Linux box.
With small modifications it can also be used to get the data directly into a data ware house server.
Refer to [URL]http://www.postgresql.org/docs/[/URL] for further reading about PostgreSQL database maintenance.



[U][B]Compiling the Lazarus Sources into a DLL[/B][/U]

To recompile the mt4psql.dll sources into a runnable DLL you need the Lazarus Freepascal IDE.

You can get the Lazarus IDE and the Freepascal compiler here:

http://www.lazarus-ide.org/


It's really worth installing it, because the native machine code of FreePascal is a pretty nice performance boost and it's free :)
(At that point a special thanks to @7bit here who brought up the use of Lazarus to build DLLs - I owe him a beer - if not two or more ...)


Then unzip the Pascal sources into a folder named "MT4-PSQL" and edit the "copy-dll.bat" file to fit to your MT4 / Sourcecode configuration.
This batch file copies the compiled DLL into the "MQL4/Libraries" directory so that you don't have to do it manually after a compile run.


Open the "mt4psql.lpi" (Lazarus Project Information) from your filemanager (e.g. explorer) so that Lazarus fires up using all neccessary project settings.


Press "Ctrl-F9" to compile the project and notice how the time stamp of the "mt4psql.dll" in your Lazarus project directory has changed, provided there were no errors in the messages window during the compile run.


Take care that no instance of "mt4psql.dll" is used by any chart during a compile run because a sharing violation will prevent the update of the DLL in your MT4 installation by "copy-dll.bat". Sometimes MT4 does not unload a DLL so that you might be in need to shut MT4 down to recompile the library.


To check whether your DLL is in use by MT4 you might want to use the process explorer - which is aside from the use case here - such a useful process management tool so that I replaced the standard process manager of Windows with it.

https://technet.microsoft.com/en-us/sysinternals/bb896653.aspx

In the process explorer tool you can use "Ctrl-F" to find the string "mt4psql" and the process which is using it:

[attach]1671818[/attach]

 
Changes:
2015.05.10:
[LIST]
[*]	New columns in some tables to achieve more query comfort-
[*]	New functions to create OHLC values from the tick data
[*]	Template-Data for to create time frame rows.
[*]	Some more example queries and some R code
[/LIST]
 
[attach]1671499[/attach]