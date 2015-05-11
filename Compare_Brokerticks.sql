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
* This query fetches the ticks for a pair in a time range 
* from all brokers.
* It displays an abbreviation of the broker name, its demo status
* and all tick values sorted by local timestamp (reception time)
* and the broker name.
*/

select
	*
from (
	select 
		substring(b.brokername, 1, 5) as brokername,
		b.is_demo,
		p.pairname,
		t.*
	from 
		t_mt4_pairdata p 
		join t_mt4_brokers b using (broker_id) 
		join t_mt4_ticks t using (pair_id) 
) i
where
	i.pairname='GBPJPY' and 
	i.loctimestamp>='2015-05-07 23:15:00'::timestamp and 
	i.loctimestamp<'2015-05-07 23:15:30'::timestamp
order by
	i.loctimestamp,
	i.brokername
