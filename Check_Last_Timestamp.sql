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
*
* This query gets the number of average ticks per minute by broker and pair
* and displays the pair name, the broker name and their demo status
* as well as their time zone and the timestamp of the last tick received.
* sorted by alias name, broker name and live status.
*
* Useful to check if the API did not receive any tick from a broker
* 
*/
select
	a.pairname as aliasname,
	p.pair_id,
	b.broker_id,
	b.brokername,
	b.is_demo,
	b.broker_timezone,
	-- *,
	(select
		ttimestamp
	from
		t_mt4_ticks t
	where 
		t.pair_id=p.pair_id
	order by
		t.ttimestamp desc
	limit 1
	) as last_tick,
	(select
		round(avg(tckcnt),0)
	 from (
		select
			count(*) as tckcnt
		from
			t_mt4_ticks t
		where 
			t.pair_id=p.pair_id
		group by
			extract(minute from ttimestamp)
	 ) i
	) as avg_ticks_per_minute
from
	t_mt4_pairdata p
	join t_mt4_brokers b using (broker_id) 
	left join t_mt4_pairaliases pa using (pair_id)
	left join t_mt4_aliasnames a using (alias_id)
-- where a.pairname='EURUSD'
order by
	a.pairname, 
	b.brokername,
	b.is_demo

