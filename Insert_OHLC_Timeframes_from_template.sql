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
* This scriptlet is used to populate the ohlc time frame table
* with values obtained from the "DUMMY" pair which is 
* used as a template in this way.
* Change the number of the pair_id in the inner select
* statement below where
*
*/
insert into t_mt4_pair_timeframes (pair_id, ttimeframe, timeframe_name)
select
	i.*
from (
	select 
		-- change this number to your pair_id needed
		15 as pair_id,
		ttimeframe,
		timeframe_name
	from 
		t_mt4_pair_timeframes tf 
		join t_mt4_pairdata p using (pair_id) 
	where 
		pairname='DUMMY'
) i 
-- prevent duplicate entries
left join t_mt4_pair_timeframes ttf on (
	ttf.pair_id=i.pair_id and
	ttf.ttimeframe=i.ttimeframe
)
where
	ttf.ttimeframe is null;
