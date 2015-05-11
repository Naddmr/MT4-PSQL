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
* This query is an approach to make use of the milliseconds of the local time stamps
* to create a synthetic timestamp out of the broker time to obtain a primary key 
* which is related to the broker time stamp. 
*
* Hint: Does not work, as even milliseconds are not fine grained enough to achieve this
*
*/

select
	i.v_brokername,
	i.is_demo,
	i.loctimestamp,
	i.tick_cnt,
	v_lochour,
	v_thour,
	i.ttimestamp,
	v_dt_ms,
	i.ttimestamp + (to_char(v_dt_ms, '99999999999') || ' ms')::interval as synthetic_ts,
	i.isbadtick,
	i.dbid,
	i.dask
	
from (
	select 
		substring(b.brokername, 1,4) as v_brokername,
		is_demo,
		p.pairname,
		extract(hour from loctimestamp) as v_lochour,
		extract(hour from ttimestamp) as v_thour, 
		round(
			(
				( (60000*extract(minutes from loctimestamp)) + extract(ms from loctimestamp) ) -
				( (60000*extract(minutes from ttimestamp))   + extract(ms from ttimestamp) )
				
			)::numeric
		,0) as v_dt_ms,
		t.*
	from 
		t_mt4_pairdata p 
		join t_mt4_brokers b using (broker_id) 
		join t_mt4_ticks t using (pair_id) 
) i
where
	i.pairname='GBPJPY' and 
	i.loctimestamp>='2015-05-07 23:14:30'::timestamp and 
	i.loctimestamp<'2015-05-07 23:16'::timestamp and
	not is_demo
order by
	i.loctimestamp,
	i.v_brokername
