program MT4_4_PQ_MainWindow;

{$mode objfpc}{$H+}

uses
	cMem,
	{$IFDEF UNIX}{$IFDEF UseCThreads}
		cthreads,
	{$ENDIF}{$ENDIF}
	Interfaces, // this includes the LCL widgetset
	Forms,
        umt4_pq_writerwindow, uMT4_PQ_ThreadClass, uMT4_PQ_WriterClass,
umt4_PQ_QueueManager
{ you can add units after this };

{$R *.res}

begin
		RequireDerivedFormResource := True;
		Application.Initialize;
		Application.CreateForm(TfrmWriterWindow, frmWriterWindow);
		Application.Run;
end.

