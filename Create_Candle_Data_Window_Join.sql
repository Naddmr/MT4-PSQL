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
* This query creates a view on the tick values 
* which resembles OHLC values of a certain time frame
* 
* It uses window functions of PostgreSQL to make aggregates 
* without the need to "group by" in a subselect and achieves
* index usage on t_mt4_ticks in this way.
*
*/

select distinct
	i.timeframe_id,
	i.v_from_time,
	-- open
	first_value(tt.dbid) over w_timeframe_time_from as v_d_open_bid,
	first_value(tt.dask) over w_timeframe_time_from as v_d_open_ask,
	-- high
	max(tt.dbid) over w_timeframe_time_from as v_d_high_bid,
	max(tt.dask) over w_timeframe_time_from as v_d_high_ask,
	-- low
	min(tt.dbid) over w_timeframe_time_from as v_d_low_bid,
	min(tt.dask) over w_timeframe_time_from as v_d_low_ask,
	-- close
	last_value(tt.dbid) over w_timeframe_time_from as v_d_close_bid,
	last_value(tt.dask) over w_timeframe_time_from as v_d_close_ask,
	-- volume
	sum(dvolume) over w_timeframe_time_from as v_d_volume,
	count(*) over w_timeframe_time_from as v_d_tickvolume
from (
	-- generate a table of timeframe data 
	select distinct
		-- payload as a base to build OHLC values
		tf.timeframe_id,
		t.pair_id,
		normalize_timeframe(t.ttimestamp, tf.ttimeframe) as v_from_time,
		normalize_timeframe(t.ttimestamp, tf.ttimeframe) +  (to_char(tf.ttimeframe, '999999999999') || ' seconds')::interval as v_until_time
	from
		t_mt4_brokers b
		join t_mt4_pairdata p using (broker_id)
		join t_mt4_ticks t using (pair_id)
		join t_mt4_pair_timeframes tf using (pair_id)
	where
	 	b.broker_id=2 and
	   	p.pair_id=20 and
	   	t.ttimestamp>='2015-05-08 08:00'::timestamp and
	   	t.ttimestamp<='2015-05-08 08:07'::timestamp and
	   	tf.timeframe_name='M1'
	order by
		tf.timeframe_id,
		v_from_time
) i join t_mt4_ticks tt on (
	tt.pair_id=i.pair_id and 
	tt.ttimestamp>=i.v_from_time and 
	tt.ttimestamp<i.v_until_time
)
window 
	w_timeframe_time_from as (
		partition by i.timeframe_id, i.v_from_time 
		order by i.v_from_time, tt.loctimestamp 
		rows between unbounded preceding and unbounded following
	);
