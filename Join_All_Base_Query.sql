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


select
	*
from
	t_mt4_brokers b
	join t_mt4_pairdata p using (broker_id)
	join t_mt4_pairaliases pa using (pair_id)
	join t_mt4_aliasnames a using (alias_id)
	join t_mt4_pair_timeframes tf using (pair_id)
	join t_mt4_ticks t using (pair_id)
where
	a.pairname='DAX' and
	t.ttimestamp>='2015-05-08 08:00'::timestamp and
	t.ttimestamp<'2015-05-08 08:10'::timestamp and
	tf.ttimeframe=60
