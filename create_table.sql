/*
    Copyright 2015 Naddmr, http://www.forexfactory.com

    This file is part of the mt4psql project.

    mt4psql is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    mt4psql is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mt4psql.  If not, see <http://www.gnu.org/licenses/>.
*/

/*
* This is the DDL of the mtforex database.
* It creates all neccessary structures and functions
* needed by the Lazarus project mt4psql
*
*/

-- create database mtforex;
-- \c mtforex

drop table if exists t_mt4_brokers cascade;
create table t_mt4_brokers (
	broker_id	serial,
	brokername	varchar(256),
	broker_timezone	varchar(256),
	is_demo		boolean,
	timeCreated	timestamp with time zone not null default now(),
	constraint pk_mt4_brokers primary key (broker_id)
);
comment on table t_mt4_brokers is 'Contains all account and broker relevant information. Delete a row from here and all ticks and candles if this broker/account will be deleted too';
comment on column t_mt4_brokers.broker_id	is 'Primary key of the broker table. Used to reference a broker/account row.';
comment on column t_mt4_brokers.brokername	is 'Name of the broker as gotten from the AccountCompany() call in MQL4.';
comment on column t_mt4_brokers.broker_timezone	is 'Timezone of the brokers server. Must be configured manually on the MQL side.';
comment on column t_mt4_brokers.is_demo		is 'Determines whether the account is demo (t) or live (f)';


drop table if exists t_mt4_pairdata cascade;
create table t_mt4_pairdata (
	pair_id		serial,
	broker_id	integer not null,
	pairname	varchar(16),
	point		numeric(15,5),
	digits		numeric(15,5),
	timeCreated	timestamp with time zone not null default now(),
	constraint pk_mt4_pairdata primary key (pair_id),
	constraint fk_pair_broker foreign key (broker_id) references t_mt4_brokers (broker_id) on update cascade on delete cascade
);
comment on table t_mt4_pairdata is 'Contains all account and broker relevant information';
comment on column t_mt4_pairdata.pair_id	is 'Primary key of the pairdata table. Used to reference a pairdata row which references a broker row.';
comment on column t_mt4_pairdata.broker_id	is 'Foreign key into the broker table. References the broker of the pair';
comment on column t_mt4_pairdata.pairname	is 'Name of the pair as gotten from the Symbol() call on the MQL side.';
comment on column t_mt4_pairdata.point		is 'Decimal points of the pair as gotten from the "Point" variable on the MQL side.';
comment on column t_mt4_pairdata.digits		is 'Digits of the pair as gotten from the Digits variable on the MQL side.';


drop table if exists t_mt4_aliasnames cascade;
create table t_mt4_aliasnames (
	alias_id	serial,
	pairname	varchar(128),
	timeCreated	timestamp with time zone not null default now(),
	constraint pk_mt4_aliases primary key (alias_id)
);
comment on table t_mt4_aliasnames is 'Contains an alias name for different pairnames.';
comment on column t_mt4_aliasnames.alias_id	is 'Primary key of the aliasnames table.';
comment on column t_mt4_aliasnames.pairname	is 'Common aliasname of the pair (e.g. SP500 for SPX500USD SPX500 ...)';

insert into t_mt4_aliasnames (pairname) values 
	('SPX'),	-- 1
	('DOW'),	-- 2
	('DAX');	-- 3


drop table if exists t_mt4_pairaliases;
create table t_mt4_pairaliases (
	pair_id		integer,
	alias_id	integer,
	constraint pk_mt4_aliaspairs primary key (pair_id, alias_id),
	constraint fk_pairalias_pairs	foreign key (pair_id) references t_mt4_pairdata (pair_id) on update cascade on delete cascade,
	constraint fk_pairalias_aliases	foreign key (alias_id) references t_mt4_aliasnames (alias_id) on update cascade on delete cascade
);

comment on table t_mt4_pairaliases is 'Contains an alias name for different pairnames.';
comment on column t_mt4_pairaliases.alias_id	is 'References exactly one alias name for this row.';
comment on column t_mt4_pairaliases.pair_id	is 'References all mt4_pairdata from this alias_id row (e.g. SP500 for SPX500USD SPX500 ...)';


drop table if exists t_mt4_ticks;
create table t_mt4_ticks (
	pair_id		integer not null,
	loctimestamp	timestamp with time zone,
	tick_cnt	integer,
	ttimestamp	timestamp with time zone,
	isBadTick	bool,
	dbid		numeric(15,5),
	dask		numeric(15,5),
	dlast		numeric(15,5),
	dvolume		numeric(15),
	constraint pk_mt4_ticks primary key (pair_id, loctimestamp, tick_cnt),
	constraint fk_tick_pairdata foreign key (pair_id) references t_mt4_pairdata (pair_id) on update cascade on delete cascade
);
comment on table t_mt4_ticks is 'Contains all ticks - their bid/ask/timestamps. Pair_id/ttimestamp are the primary key of a row in this table.';
comment on column t_mt4_ticks.pair_id		is 'Foreign key of the pairdata table. Used to reference a pairdata row which references a broker row.';
comment on column t_mt4_ticks.loctimestamp	is 'Timestamp of the local time from the writing machine of a tick.';
comment on column t_mt4_ticks.tick_cnt		is 'Number of the tick received in the same millisecond of LOCTIMESTAMP.';
comment on column t_mt4_ticks.ttimestamp	is 'Broker timestamp of a tick with its respective time zone information.';
comment on column t_mt4_ticks.isBadTick		is 'Is TRUE when a tick with an older broker timestamp arrives as current tick. FALSE otherwise.';
comment on column t_mt4_ticks.dBid		is 'Bid price of a tick as gotten from the MQLTick structure after a SymbolInfoTick() call.';
comment on column t_mt4_ticks.dAsk		is 'Ask price of a tick as gotten from the MQLTick structure after a SymbolInfoTick() call.';
comment on column t_mt4_ticks.dLast		is 'Last traded price of a tick as gotten from the MQLTick structure after a SymbolInfoTick() call.';
comment on column t_mt4_ticks.dVolume		is 'Volume of a tick as gotten from the MQLTick structure after a SymbolInfoTick() call.';


drop table if exists t_mt4_pair_timeframes cascade;
create table t_mt4_pair_timeframes (
	timeframe_id	serial,
	pair_id		integer not null,
	ttimeframe	integer,
	timeframe_name	varchar(128),
	timeCreated	timestamp with time zone not null default now(),
	constraint pk_mt4_timeframes primary key (timeframe_id),
	constraint fk_timeframe_pairdata foreign key (pair_id) references t_mt4_pairdata (pair_id) on update cascade on delete cascade
);
comment on table t_mt4_pair_timeframes is 'Contains the information about which timeframes are available for a OHLC candle or other tick aggregates. Is referenced by the OHLC table';
comment on column t_mt4_pair_timeframes.pair_id		is 'Foreign key of the pairdata table. Used to reference a pairdata row which references a broker row.';
comment on column t_mt4_pair_timeframes.ttimeframe	is 'Seconds of the timeframe (60(M1),300(M5),900(M15),1800(M30),3600(M60), ... or whatever timeframe is derived from the ticks).';
comment on column t_mt4_pair_timeframes.timeframe_name	is 'Name of the timeframe (60(M1),300(M5),900(M15),1800(M30),3600(M60).';

drop table if exists t_mt4_ohlc cascade;
create table t_mt4_ohlc (
	timeframe_id	integer not null,
	ttimestamp	timestamp with time zone,
	dOpenBid	numeric(15,5),
	dOpenAsk	numeric(15,5),
	dHighBid	numeric(15,5),
	dHighAsk	numeric(15,5),
	dLowBid		numeric(15,5),
	dLowAsk		numeric(15,5),
	dCloseBid	numeric(15,5),
	dCloseAsk	numeric(15,5),
	dTradeVolume	Numeric(15),
	dTickVolume	Numeric(15),
	constraint pk_mt4_candles primary key (timeframe_id, ttimestamp),
	constraint fk_candle_timeframes foreign key (timeframe_id) references t_mt4_pair_timeframes (timeframe_id) on update cascade on delete cascade
);

comment on table t_mt4_ohlc is 'Contains the OHLC candles derived from the respective tick data.';
comment on column t_mt4_ohlc.timeframe_id	is 'Foreign key of the timeframe table. Used to reference a timeframe row which references a pair row which references a broker.';
comment on column t_mt4_ohlc.dOpenBid		is 'Open bid price of the candle. Derived from the first tick of a timeframe.';
comment on column t_mt4_ohlc.dOpenAsk		is 'Open ask price of the candle. Derived from the first tick of a timeframe.';
comment on column t_mt4_ohlc.dHighBid		is 'Highest Bid price of the candle. Derived from the highest tick of a timeframe.';
comment on column t_mt4_ohlc.dHighAsk		is 'Highest Ask price of the candle. Derived from the highest tick of a timeframe.';
comment on column t_mt4_ohlc.dLowBid		is 'Lowest Bid price of the candle. Derived from the lowest tick of a timeframe.';
comment on column t_mt4_ohlc.dLowAsk		is 'Lowest Ask price of the candle. Derived from the lowest tick of a timeframe.';
comment on column t_mt4_ohlc.dCloseBid		is 'Close Bid price of the candle. Derived from the last tick of a timeframe.';
comment on column t_mt4_ohlc.dCloseAsk		is 'Close Ask price of the candle. Derived from the last tick of a timeframe.';
comment on column t_mt4_ohlc.dTradeVolume	is 'Traded volume (if applicable). Sum of all trade volumes of a timeframe.';
comment on column t_mt4_ohlc.dTickVolume	is 'Tick volume. Count of all ticks of a timeframe ';

-- 
--
-- now populate the tables to get some templates
insert into t_mt4_brokers (brokername, broker_timezone, is_demo) values ('Dummybroker', 'UTC', true);
insert into t_mt4_pairdata (broker_id, pairname, point, digits) values ( (select broker_id from t_mt4_brokers order by timecreated desc limit 1), 'DUMMY', 1, 0);
insert into t_mt4_aliasnames (pairname) values ('DUMMY');
insert into t_mt4_pairaliases (pair_id, alias_id) values 
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),
	 (select alias_id from t_mt4_aliasnames order by timecreated desc limit 1));
insert into t_mt4_pair_timeframes (pair_id, ttimeframe, timeframe_name) values
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	        30, 	'S30'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	        60, 	'M1'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	      5*60, 	'M5'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	     15*60, 	'M15'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	     30*60, 	'M30'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	     60*60, 	'H1'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	   4*60*60, 	'H4'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	   8*60*60, 	'H8'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	  24*60*60, 	'D1'),
	((select pair_id from t_mt4_pairdata order by timecreated desc limit 1),	7*24*60*60, 	'W1');

--
--
-- include functions to create timeframe normalized timestamp values
\i func_normalize_timeframe.sql
--
-- Include the function to create OHLC values from ticks
\i func_do_populate_ohlc.sql

