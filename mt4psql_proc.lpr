library mt4psql_proc;

{$mode objfpc}{$H+}

uses
	cMem,
        Classes,
        Windows,
        SysUtils,
        DateUtils,
        uPQWriterDefinitions,
        upq_process_dispatcher;

function pqInit(
   	pConfigFileName		: pWideChar;
	pEAName 		: pWideChar;
        pPairName 		: pWideChar;
        pBrokerName		: pWideChar;
        pIsDemo			: DWORD;
        pPoint			: Double;
        pDigits			: Double
) : LongInt; stdcall;
var
	 hdl	  : LongInt;
begin
     hdl:=LongInt(
     		PQProcDispatcherClass.Create(
			pConfigFileName,
			pEAName,
        		pPairName,
        		pBrokerName,
        		pIsDemo,
        		pPoint,
        		pDigits
     		)
     );
     exit(hdl);
end;

procedure pqDeInit(pHdl		: LongInt) ; stdcall;
begin
        if (PQProcDispatcherClass(pHdl)<>NIL) then
     		PQProcDispatcherClass(pHdl).free;
end;

procedure DispatchTick(
          pHdl	    	  	: LongInt;
          pTick			: pMQLTickRow
); stdcall;
begin
     	PQProcDispatcherClass(pHdl).DispatchTick(pTick);
end;

function isValidHandle(
          pHdl			: LongInt
):Integer;
var
        rc	: Integer;
begin
     	// if (PQDispatcher(pHdl)<>NIL) then
        rc:=PQProcDispatcherClass(pHdl).GetisValid();
     	exit( rc );
end;

exports
	pqInit,
	pqDeInit,
	DispatchTick,
	isValidHandle
;

begin
end.
