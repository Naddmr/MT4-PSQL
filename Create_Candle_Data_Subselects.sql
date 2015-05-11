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

-- This naive approach to employ subselects 
-- to fetch the candle data is way too slow 
-- to be used.
--
-- It's therefore only retained as a bad example
-- of good intentions gone wrong.

select
	i.timeframe_id,
	i.pair_id,
	i.v_from_time,
	i.v_until_time,
	(
		select
			t.dbid
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
		order by
			t.loctimestamp asc
		limit 1
	) as v_d_open_bid,
	(
		select
			t.dask
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
		order by
			t.loctimestamp asc
		limit 1
	) as v_d_open_ask,
	(
		select
			max(t.dbid)
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
	) as v_d_high_bid,
	(
		select
			max(t.dask)
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
	) as v_d_high_ask,
	(
		select
			min(t.dbid)
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
	) as v_d_low_bid,
	(
		select
			min(t.dask)
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
	) as v_d_low_ask,
	(
		select
			t.dbid
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
		order by
			t.loctimestamp desc
		limit 1
	) as v_d_close_bid,
	(
		select
			t.dask
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
		order by
			t.loctimestamp desc
		limit 1
	) as v_d_close_ask,
	(
		select
			sum(t.dvolume)
		from
			t_mt4_ticks t
		where
			t.pair_id=i.pair_id and
			t.ttimestamp>=i.v_from_time and
			t.ttimestamp<i.v_until_time
	) as v_volume
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
	   	t.ttimestamp<='2015-05-08 22:07'::timestamp and
	   	tf.ttimeframe=60
	order by
		tf.timeframe_id,
		v_from_time
) i
order by
	i.timeframe_id,
	i.v_from_time
