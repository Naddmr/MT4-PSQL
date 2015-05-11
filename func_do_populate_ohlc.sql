/*  Copyright 2015 Naddmr, http://www.forexfactory.com

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
*  This function populates the t_mt4_ohlc table
*  It uses the pair_id and a timerange as parameters.
*  It loops over any timeframe_id found in the t_mt4_pair_timeframes and creates each 
*  timeframe separately starting with the lowest value first.
* 
* CAVEAT: The last tick of a timeframe might not be the right close value of the last candle!
* Imagine running the function on a thursday at 17:00 - the close of this day 
* would be on 17:00 then instead of 23:59.59)
*/
create or replace function do_populate_ohlc (
	in_pair_id	t_mt4_pairdata.pair_id%type,
	in_from_time	t_mt4_ticks.ttimestamp%type,
	in_until_time	t_mt4_ticks.ttimestamp%type
) returns bigint 
as $$
declare
	pair_rec	record;
	broker_rec	record;
	timeframe_rec	record;
	ohlc_rec	record;
	rc		bigint;
	rc1		bigint;
	from_time	t_mt4_ticks.ttimestamp%type;
	until_time	t_mt4_ticks.ttimestamp%type;
	tick_cnt	bigint;
begin
	rc:=0;
	rc1:=0;
	--
	-- fetch some more information about the 
	-- pairdata (broker_id and pairname)
	select
		p.*
		into pair_rec
	from
		t_mt4_pairdata p
	where
		p.pair_id=in_pair_id;
	--
	if not found then 
		raise notice 'do_populate_ohlc: in_pair_id=% has no pair data available', in_pair_id;
		return rc;
	end if;
	--
	-- check whether a broker exists for the given pair
	select
		b.*
		into broker_rec
	from
		t_mt4_brokers b
	where
		b.broker_id=pair_rec.broker_id;
	if not found then 
		raise notice 'do_populate_ohlc: broker_id=% from pair_id=% has broker data available', pair_rec.broker_id, in_pair_id;
		return rc;
	end if;
	--
	-- fetch the first time stamp from the tick data according to the parameters
	select
		t.ttimestamp
		into from_time
	from
		t_mt4_ticks t
	where
		t.pair_id=in_pair_id and
		t.ttimestamp>=in_from_time
	order by 
		t.ttimestamp asc
	limit 1;
	if not found then 
		raise notice 'do_populate_ohlc: pair_id=% has no ticks after ', in_pair_id, to_char(in_from_time, 'YYYY-MM-DD HH24:MI:SS');
		return rc;
	end if;
	--
	-- fetch the last time stamp from the tick data according to the parameters
	select
		t.ttimestamp
		into until_time
	from
		t_mt4_ticks t
	where
		t.pair_id=in_pair_id and
		t.ttimestamp>=from_time and
		t.ttimestamp<=in_until_time
	order by 
		t.ttimestamp desc
	limit 1;
	if not found then 
		raise notice 'do_populate_ohlc: pair_id=% has no ticks before ', in_pair_id, to_char(in_until_time, 'YYYY-MM-DD HH24:MI:SS');
		return rc;
	end if;
	select
		count(*)
		into tick_cnt
	from
		t_mt4_ticks t
	where
		t.pair_id=in_pair_id and
		t.ttimestamp>=from_time and
		t.ttimestamp<=until_time;
		
	raise notice 'do_populate_ohlc: id=% (%/%)                from % until % has % ticks available', 
		in_pair_id, 
		pair_rec.pairname,
		broker_rec.brokername,
		to_char(from_time, 'YYYY-MM-DD HH24:MI:SS'),
		to_char(until_time, 'YYYY-MM-DD HH24:MI:SS'),
		to_char(tick_cnt, '999999999999');
	
	--
	-- Loop over each timeframe row for that pair_id
	for timeframe_rec in 
		select
			*
		from
			t_mt4_pair_timeframes tf
		where
			tf.pair_id=in_pair_id
		order by
			ttimeframe asc
	loop
		-- mumble something to the logs
		raise notice 'do_populate_ohlc: id=% (%/%) tf=% - from % until %              starting at %', 
			in_pair_id, 
			pair_rec.pairname,
			broker_rec.brokername,
			to_char(timeframe_rec.ttimeframe, '99999999'),
			to_char(from_time, 'YYYY-MM-DD HH24:MI:SS'),
			to_char(until_time, 'YYYY-MM-DD HH24:MI:SS'),
			to_char(clock_timestamp(), 'YY-MM-DD HH24:MI:SS');
		-- TODO: Update the last ohlc in case if we missed some ticks since the last run. (CAVEAT from above!!)
		select
			*
			into ohlc_rec
		from
			t_mt4_ohlc o
		where
			o.timeframe_id=timeframe_rec.timeframe_id and
			o.ttimestamp>=in_from_time
		order by
			o.ttimestamp desc
		limit 1;
		if found then 
			raise notice 'do_populate_ohlc: id=% (%/%) tf=% - from % until %: Found OHLC row for update! NOT IMPLEMENTED YET!', 
				in_pair_id, 
				pair_rec.pairname,
				broker_rec.brokername,
				to_char(timeframe_rec.ttimeframe, '99999999'),
				to_char(from_time, 'YYYY-MM-DD HH24:MI:SS'),
				to_char(until_time, 'YYYY-MM-DD HH24:MI:SS');
		end if;
		--
		-- insert directly into the table by using a little trick in the 
		-- select where clause below.
		insert into t_mt4_ohlc (
			timeframe_id,
			ttimestamp,
			dopenbid,
			dopenask,
			dhighbid,
			dhighask,
			dlowbid,
			dlowask,
			dclosebid,
			dcloseask,
			dtradevolume,
			dtickvolume
		) 
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
				b.broker_id=broker_rec.broker_id and
				p.pair_id=in_pair_id and
				t.ttimestamp>=from_time and
				t.ttimestamp<=until_time and
				tf.timeframe_id=timeframe_rec.timeframe_id
			-- order by
-- 				tf.timeframe_id,
-- 				v_from_time
		) i join t_mt4_ticks tt on (
			tt.pair_id=i.pair_id and 
			tt.ttimestamp>=i.v_from_time and 
			tt.ttimestamp<i.v_until_time
		)
		-- this left join ensures that no duplicate rows are inserted
		left join (
			-- select the OHLC subset affected only.
			select
				oo.timeframe_id,
				oo.ttimestamp
			from
				t_mt4_ohlc oo
			where
				oo.timeframe_id=timeframe_rec.timeframe_id and
				oo.ttimestamp>=normalize_timeframe(from_time, timeframe_rec.ttimeframe ) and
				oo.ttimestamp<=normalize_timeframe(until_time, timeframe_rec.ttimeframe )
		) o on (
			o.timeframe_id=timeframe_rec.timeframe_id and 
			o.ttimestamp=i.v_from_time
		)
		where
			o.timeframe_id is null
		window 
			w_timeframe_time_from as (
				partition by i.timeframe_id, i.v_from_time 
				order by i.v_from_time, tt.loctimestamp 
				rows between unbounded preceding and unbounded following
			)
		;
		-- get the number of rows affected
		GET DIAGNOSTICS rc1 = ROW_COUNT;
		rc:=rc+rc1;
		-- mumble something into the logs ... :-)
		raise notice 'do_populate_ohlc: id=% (%/%) tf=% - from % until % had % candles at %', 
			in_pair_id, 
			pair_rec.pairname,
			broker_rec.brokername,
			to_char(timeframe_rec.ttimeframe, '99999999'),
			to_char(from_time, 'YYYY-MM-DD HH24:MI:SS'),
			to_char(until_time, 'YYYY-MM-DD HH24:MI:SS'),
			to_char(rc1, '99999999'),
			to_char(clock_timestamp(), 'YY-MM-DD HH24:MI:SS');
	end loop;
	-- mumble something to the logs
	raise notice 'do_populate_ohlc: id=% (%/%) tf=      ALL - from % until % had % candles at %', 
		in_pair_id, 
		pair_rec.pairname,
		broker_rec.brokername,
		to_char(in_from_time, 'YYYY-MM-DD HH24:MI:SS'),
		to_char(in_until_time, 'YYYY-MM-DD HH24:MI:SS'),
		to_char(rc, '99999999'),
		to_char(clock_timestamp(), 'YY-MM-DD HH24:MI:SS');
	return rc;
end
$$ language 'plpgsql';
