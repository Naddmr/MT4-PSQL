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

-- 
select do_populate_ohlc(
	20,
	'2015-01-01'::timestamp,
	'2015-12-31'::timestamp
);

select do_populate_ohlc(
	4,
	'2015-01-01'::timestamp,
	'2015-12-31'::timestamp
);
-- 
-- 
select do_populate_ohlc(
	15,
	'2015-01-01'::timestamp,
	'2015-12-31'::timestamp
);
-- 
-- 
-- vacuum analyze;

