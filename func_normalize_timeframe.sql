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


create or replace function normalize_timeframe(
	in_ttimestamp	t_mt4_ticks.ttimestamp%type,
	in_timeframe	int
) returns timestamp with time zone
as $$
declare
	rc		t_mt4_ticks.ttimestamp%type;
begin
	rc:=timestamp with time zone 'epoch' + interval '1 second' * trunc((extract('epoch' from in_ttimestamp) / in_timeframe)) * in_timeframe;
	return rc;
end;
$$ language 'plpgsql';

