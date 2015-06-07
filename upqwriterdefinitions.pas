{
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
}

unit uPQWriterDefinitions;

{$mode objfpc}{$H+}

interface

uses
	cMem,
        Classes,
        Windows,
        SysUtils,
        DateUtils;
type
tBufArrayLong	= Array[0..127] of char;
tBufArrayShort	= Array[0..64] of char;
// Representation of a tick row in MQL
TMQLTickRow = packed record
        time	: INT64;
        bid,
        ask,
        last	: Double;
        volume	: LongInt;
end;
pMQLTickRow = ^TMQLTickRow;
// A tick row with milliseconds
TSQLTickRow = packed record
        pairID		: Integer;
        MQLTick		: TMQLTickRow;
        BrokerTimeZone	: tBufArrayLong;
        localTime	: TTimeStamp;
        TickTime	: TDateTime;
        TickCounter	: DWORD;
end;
pSQLTickRow = ^TSQLTickRow;
//
// A broker definition row
TSQLBrokerRow = packed record
        broker_id	: Integer;
        is_demo		: boolean;
        broker_name	: tBufArrayLong;
        broker_timezone	: tBufArrayLong;
end;
pSQLBrokerRow = ^TSQLBrokerRow;
//
// A pair definition row
TSQLPairRow = packed record
        pair_id		: Integer;
        broker_id	: Integer;
        pair_name	: tBufArrayShort;
        point		: Double;
        Digits		: Double;
end;
pSQLPairRow = ^TSQLPairRow;
//
TFiFoRecord = packed record
        read_idx	: DWORD;
        write_idx	: DWORD;
end;
pFIFORecord = ^TFiFoRecord;


PQConfigClass = Class
public
        ThisPairID			: DWORD;
        ThisBrokerID			: DWORD;
        ThisPairName			: AnsiString;
        ThisBrokerTimeZone		: AnsiString;
        ThisMachineTimezone		: AnsiString;
        ThisBrokerName			: AnsiString;
        ThisAccountIsDemo		: DWORD;
	ThisEAName			: AnsiString;
        ThisTimeframe			: Integer;
        ThisPairPoint			: Double;
        ThisPairDigits			: Double;
        DBHostname			: AnsiString;
     	DBHostPort			: DWORD;
     	DBName				: AnsiString;
     	DBUserName			: AnsiString;
     	DBPassword			: AnsiString;
        MaxRetries			: DWORD;
        PollingInterval			: DWORD;
        // Two process solution only
        ShareMemNamePrefix		: AnsiString;
        PairShareMemName		: AnsiString;
        PairMutexName			: AnsiString;
        BrokerShareMemName		: AnsiString;
        BrokerMutexName			: AnsiString;
        TickShareMemName		: AnsiString;
        TickMutexName			: AnsiString;
        MaxCharts			: DWORD;
        MaxBrokers			: DWORD;
        MaxTicks			: DWORD;
        DBThreadCount			: DWORD;
        //
        constructor create(
		pBrokerTimeZone		: WideString;
                pMachineTimeZone	: WideString;
		pEAName 		: WideString;
		pPairName 		: WideString;
                pBrokerName		: WideString;
                pIsDemo			: DWORD;
                pTimeframe		: Integer;
                pPoint			: Double;
        	pDigits			: Double;
                pPollingInterval	: DWORD;
		pDBHostname		: WideString;
		pDBHostPort		: Integer;
		pDBName			: WideString;
		pDBUsername		: WideString;
		pDBPassword		: WideString;
                pMaxRetries		: DWORD
        );
        destructor destroy(); override;
        function ReadSettings(pFileName	: AnsiString) : boolean;
        procedure setSHMBaseName(pBaseName	: AnsiString);
        function StackTrace(pException : Exception) : String;
private
        // log a message to the debug monitor
	procedure Log(AMessage: WideString);
	// log a formatted message to the debug monitor
	procedure Log(AMessage: WideString; AArgs: array of const);

end;
//#########################################
PQShareMemClass = Class
protected
        RowSize			: DWORD;
        RowCount		: DWORD;
        ShareMemBaseName	: AnsiString;
        ShareMemSize		: DWORD;
        ShareMemHdl		: THandle;
        ShareMemPtr		: Pointer;
        DataPtr			: Pointer;
        MutexName		: AnsiString;
        MutexHdl		: THandle;
public
        constructor create(
                	pSHMBaseName	: AnsiString;
                	pRowSize	: DWORD;
                	pRowCount	: DWORD
	);
        destructor destroy(); override;
        function get(pIndex	: DWORD) : Pointer;
        function getLast() : Pointer;
        procedure add(pRow	: Pointer);
        procedure AddRing(pRow	: Pointer);
        function  GetRing():Pointer;
        procedure Lock();
        procedure UnLock();
        //
        property wRowSize : DWORD read RowSize;
        property FiFoPtr  : Pointer read ShareMemPtr;
        property RowPtr  : Pointer read DataPtr;
private
        // log a message to the debug monitor
	procedure Log(AMessage: WideString);
	// log a formatted message to the debug monitor
	procedure Log(AMessage: WideString; AArgs: array of const);
end;

//
const
	BROKER_SHAREMEM_SUFFIX	: AnsiString =	'_BROKERS';
        PAIR_SHAREMEM_SUFFIX	: AnsiString =	'_PAIRS';
        TICKS_SHAREMEM_SUFFIX	: AnsiString =	'_TICKS';
        SEM_MUTEX_PREFIX	: AnsiString =	'SEM_';

// ########################################
implementation

constructor PQShareMemClass.create(
        	pSHMBaseName	: AnsiString;
                pRowSize	: DWORD;
                pRowCount	: DWORD
);
var
        err		: DWORD;
        i		: DWORD;
begin
        ShareMemBaseName:=pSHMBaseName;
        MutexName:=SEM_MUTEX_PREFIX + ShareMemBaseName;
        RowSize:=pRowSize;
        RowCount:=pRowCount;
        self.log('PQShareMemClass.create: SHM-Name = %s', [ShareMemBaseName]);
        ShareMemSize:=(RowCount+1)*pRowSize+sizeof(TFiFoRecord);
        self.log('PQShareMemClass.create: SHM-Size = %d', [ShareMemSize]);
        ShareMemHdl:=CreateFileMapping($FFFFFFFF, nil, PAGE_READWRITE, 0, ShareMemSize, pChar(ShareMemBaseName));
        if (GetLastError()=ERROR_ALREADY_EXISTS) then begin
                self.log('PQShareMemClass.create: SHM-hdl %d already exists - reopening', [ShareMemHdl]);
                CloseHandle(self.ShareMemHdl);
        	ShareMemHdl:=OpenFileMapping(FILE_MAP_ALL_ACCESS, true, pChar(ShareMemBaseName));
	end;
	self.log('PQShareMemClass.create: SHM-hdl = %d', [ShareMemHdl]);
        ShareMemPtr:=NIL;
        i:=0;
        while (ShareMemPtr=NIL) and (i<10) do begin
        	ShareMemPtr := MapViewOfFile(ShareMemHdl, FILE_MAP_ALL_ACCESS, 0, 0, 0);
        	if (ShareMemPtr=NIL) then begin
                	err:=GetLastError();
                        self.log('PQShareMemClass.create: SHM-hdl = NIL because of err=%d', [err]);
		end;
                inc(i);
	end;
        DataPtr:=ShareMemPtr+SizeOf(TFiFoRecord);
        self.log('PQShareMemClass.create: SHM-ptr = %p', [ShareMemPtr]);
        self.log('PQShareMemClass.create: SEM-Name = %s', [MutexName]);
        MutexHdl:=CreateMutex(nil, false, pChar(MutexName));
        self.log('PQShareMemClass.create: Tick SEM-hdl = %d', [MutexHdl]);
        if (ShareMemPtr=NIL) then begin
                self.log('PQShareMemClass.create: ERROR - could not create shared memory object', [err]);
                FreeAndNil(Self);
	end;
end;

destructor PQShareMemClass.destroy();
begin
        self.log('PQShareMemClass.destroy: Invoking, releasing Mutex hdl=%d', [self.MutexHdl]);
        ReleaseMutex(self.MutexHdl);
        self.log('PQShareMemClass.destroy: Closing mutex hdl=%d ...', [self.MutexHdl]);
        CloseHandle(self.MutexHdl);
        self.log('PQShareMemClass.destroy: Unmapping SHM ptr=%p ...', [self.ShareMemPtr]);
        UnMapViewOfFile(self.ShareMemPtr);
        self.log('PQShareMemClass.destroy: Closing SHM hdl=%d ...', [self.ShareMemHdl]);
        CloseHandle(self.ShareMemHdl);
        self.log('PQShareMemClass.destroy: Done ...');
        inherited destroy;
end;

procedure PQShareMemClass.Lock();
begin
        if WaitForSingleObject(MutexHdl, INFINITE) <> WAIT_OBJECT_0 then
  		RaiseLastOSError;
end;

procedure PQShareMemClass.UnLock();
begin
	ReleaseMutex(MutexHdl);
end;

function PQShareMemClass.get(pIndex	: DWORD) : Pointer;
var
        p	: Pointer;
        rc	: Pointer;
begin
	try
                self.Lock();
		p:=RowPtr + pIndex*self.RowSize;
	finally
                self.UnLock();
	end;
	exit(p);
end;

function PQShareMemClass.getLast() : Pointer;
begin
        exit(self.get(pFIFORecord(self.ShareMemPtr)^.read_idx) );
end;

procedure PQShareMemClass.add(pRow	: Pointer);
var
        p	: Pointer;
        fp	: pFIFORecord;
begin
	try
                self.Lock();
		fp:=ShareMemPtr;
                p:=self.RowPtr;
	        inc(p, RowSize*fp^.write_idx);
                CopyMemory(p, pRow, RowSize);
        	inc(fp^.write_idx);
        finally
        	self.UnLock();
	end;
end;

procedure PQShareMemClass.AddRing(pRow	: Pointer);
var
        p	: Pointer;
        fp	: pFIFORecord;
begin
	try
                self.Lock();
		fp:=FiFoPtr;
	        p:=RowPtr;
                inc(p, fp^.write_idx*RowSize);
                CopyMemory(p, pRow, RowSize);
        	inc(fp^.write_idx);
                if (fp^.read_idx=fp^.write_idx) then begin
                        self.log('PQShareMemClass.AddRing: ERROR - FIFO overrun - record gets lost');
		end;
		if (fp^.write_idx>=RowCount) then begin
                        fp^.write_idx:=0;
		end;
	finally
        	self.UnLock();
	end;
end;

function PQShareMemClass.GetRing():Pointer;
var
        p	: Pointer;
        rc	: Pointer;
        fp	: pFIFORecord;
begin
        self.Lock();
        try
                fp:=FiFoPtr;
                p:=RowPtr;
                inc(p, fp^.read_idx*RowSize);
                rc:=cmem.Malloc(RowSize);
                CopyMemory(rc, p, RowSize);
                inc(fp^.read_idx);
                if (fp^.read_idx>RowCount) then begin
                        fp^.read_idx:=0;
		end;
	finally
                self.UnLock();
	end;
        exit(rc);
end;

// log a message to the debug monitor
procedure PQShareMemClass.Log(AMessage: WideString);
begin
	OutputDebugStringW( PWideChar(AMessage) );
end;

// log a formatted message to the debug monitor
procedure PQShareMemClass.Log(AMessage: WideString; AArgs: array of const);
begin
	Log(Format(AMessage, AArgs));
end;

// ########################################
constructor PQConfigClass.create(
		pBrokerTimeZone		: WideString;
                pMachineTimeZone	: WideString;
		pEAName 		: WideString;
		pPairName 		: WideString;
                pBrokerName		: WideString;
                pIsDemo			: DWORD;
                pTimeframe		: Integer;
                pPoint			: Double;
        	pDigits			: Double;
                pPollingInterval	: DWORD;
		pDBHostname		: WideString;
		pDBHostPort		: Integer;
		pDBName			: WideString;
		pDBUsername		: WideString;
		pDBPassword		: WideString;
                pMaxRetries		: DWORD
        );
begin
        ThisPairID:=0;
        ThisBrokerID:=0;
        ThisPairName:=Utf8ToAnsi(pPairName);
        ThisBrokerTimezone:=Utf8ToAnsi(pBrokerTimeZone);
        ThisMachineTimezone:=Utf8ToAnsi(pMachineTimeZone);
        ThisBrokerName:=Utf8ToAnsi(pBrokerName);
        ThisAccountIsDemo:=pIsDemo;
     	ThisEAName:=Utf8ToAnsi(pEAName);
        ThisTimeframe:=pTimeFrame;
        ThisPairPoint:=pPoint;
        ThisPairDigits:=pDigits;
     	DBHostname:=Utf8ToAnsi(pDBHostname);
     	DBHostPort:=pDBHostPort;
     	DBName:=Utf8ToAnsi(pDBName);
     	DBUserName:=Utf8ToAnsi(pDBUsername);
     	DBPassword:=Utf8ToAnsi(pDBPassword);
        MaxRetries:=pMaxRetries;
        PollingInterval:=pPollingInterval;
end;

destructor PQConfigClass.destroy();
begin
        inherited destroy();
end;

procedure PQConfigClass.setSHMBaseName(pBaseName	: AnsiString);
begin
        self.ShareMemNamePrefix:=pBaseName;
        //
        self.TickShareMemName:=self.ShareMemNamePrefix+TICKS_SHAREMEM_SUFFIX;
        self.TickMutexName:=SEM_MUTEX_PREFIX + self.TickShareMemName;
        //
        self.BrokerShareMemName:=self.ShareMemNamePrefix+BROKER_SHAREMEM_SUFFIX;
        self.BrokerMutexName:=SEM_MUTEX_PREFIX+self.BrokerShareMemName;
        //
        self.PairShareMemName:=self.ShareMemNamePrefix+PAIR_SHAREMEM_SUFFIX;
        self.PairMutexName:=SEM_MUTEX_PREFIX+self.PairShareMemName;

end;

function PQConfigClass.ReadSettings(pFileName	: AnsiString) : boolean;
var
        sl	: TStringList;
        ll	: TStringList;
        s	: AnsiString;
begin
        log('PQConfigClass.ReadSettings %s: About to read settings from "%s" ...', [self.ThisPairName, pFileName]);
        sl:=TStringList.Create;
        ll:=TStringList.Create;
        ll.StrictDelimiter:=true;
	try
        	sl.LoadFromFile(pFileName);
                // Parse the input
                while (sl.Count>0) do begin
                        s:= sl.Strings[0];
                        sl.Delete(0);
                        ll.Clear;
			ll.Delimiter := '=';
			ll.DelimitedText := s;
                        if (ll.Count=2) then begin
                                if (ll.Strings[0]='BrokerTimezone') then begin
                                        self.ThisBrokerTimeZone:=ll.Strings[1];
                                        log('PQConfigClass.ReadSettings %s: BrokerTimezone="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='LocalTimezone') then begin
                                        self.ThisMachineTimezone:=ll.Strings[1];
                                        log('PQConfigClass.ReadSettings %s: LocalTimezone="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='DBHostName') then begin
                                        self.DBHostname:=ll.Strings[1];
                                        log('PQConfigClass.ReadSettings %s: DBHostName="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='DBPortnumber') then begin
                                        self.DBHostPort:=StrToInt(ll.Strings[1]);
                                        log('PQConfigClass.ReadSettings %s: DBPortnumber="%s"', [self.ThisPairName, ll.Strings[1]]);
				end;

                                if (ll.Strings[0]='DBDatabaseName') then begin
                                        self.DBName:=ll.Strings[1];
                                        log('PQConfigClass.ReadSettings %s: DBDatabaseName="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='DBUserName') then begin
                                        self.DBUserName:=ll.Strings[1];
                                        log('PQConfigClass.ReadSettings %s: DBUserName="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='DBPassword') then begin
                                        self.DBPassword:=ll.Strings[1];
                                        log('PQConfigClass.ReadSettings %s: DBPassword="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='DBMaxRetries') then begin
                                        self.MaxRetries:=StrToInt(ll.Strings[1]);
                                        log('PQConfigClass.ReadSettings %s: DBMaxRetries="%s"', [self.ThisPairName, ll.Strings[1]]);
				end;
                                if (ll.Strings[0]='PollingInterval') then begin
                                        self.PollingInterval:=StrToInt(ll.Strings[1]);
                                        log('PQConfigClass.ReadSettings %s: PollingInterval="%s"', [self.ThisPairName, ll.Strings[1]]);
				end;
                                if (ll.Strings[0]='DBWriterThreads') then begin
                                        self.DBThreadCount:=StrToInt(ll.Strings[1]);
                                        log('PQConfigClass.ReadSettings %s: DBWriterThreads="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='ShareMemNamePrefix') then begin
                                        self.setSHMBaseName(ll.Strings[1]);
                                        log('PQConfigClass.ReadSettings %s: ShareMemNamePrefix="%s"', [self.ThisPairName, ll.Strings[1]]);
				end;
                                if (ll.Strings[0]='MaxCharts') then begin
                                        self.MaxCharts:=StrToInt(ll.Strings[1]);
                                        log('PQConfigClass.ReadSettings %s: MaxCharts="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='MaxBrokers') then begin
                                        self.MaxBrokers:=StrToInt(ll.Strings[1]);
                                        log('PQConfigClass.ReadSettings %s: MaxBrokers="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
                                if (ll.Strings[0]='MaxTicks') then begin
                                        self.MaxTicks:=StrToInt(ll.Strings[1]);
                                        log('PQConfigClass.ReadSettings %s: MaxTicks="%s"', [self.ThisPairName, ll.Strings[1]]);
                                end;
			end;
		end;
                ll.Destroy;
        	sl.Destroy;
                log('PQConfigClass.ReadSettings %s: Read settings from %s OK...', [self.ThisPairName, pFileName]);
		exit(true);
	except
		on E:Exception do begin
                	ll.Destroy;
        		sl.Destroy;
		end;
	end;
        log('PQConfigClass.ReadSettings %s: Reading settings from %s FAILED!...', [self.ThisPairName, pFileName]);
        exit(false);
end;

// log a message to the debug monitor
procedure PQConfigClass.Log(AMessage: WideString);
begin
	OutputDebugStringW( PWideChar(AMessage) );
end;

// log a formatted message to the debug monitor
procedure PQConfigClass.Log(AMessage: WideString; AArgs: array of const);
begin
	Log(Format(AMessage, AArgs));
end;

function PQConfigClass.StackTrace(pException : Exception) : String;
var
        i	: Integer;
        Frames	: PPointer;
        rc	: String;
begin
	Frames:=ExceptFrames;
        rc:=pException.Message;
        for i:=0 to ExceptFrameCount-1 do begin
        	rc:=rc+ BackTraceStrFunc(Frames[i]);
	end;
        exit(rc);
end;

end.

