USE [WitturToolsProd]
GO
/****** Object:  StoredProcedure [dbo].[SP_KPI_Update_MeasurePoint_Door_Cutting_SalvagniniCombinated]    Script Date: 2024. 08. 12. 9:40:47 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE .[dbo].[SP_KPI_Update_MeasurePoint_Door_Cutting_SalvagniniCombinated] AS
BEGIN

	-- be és kimeneti temptáblák deklarálása az intellisense számára
	IF 1=0
	BEGIN

		CREATE TABLE #startupParameters
		(
			 updateDateTime			DATETIME
			,selectedMeasurePointId	INT
			,nowDateTime			DATETIME
		)

		CREATE TABLE #SP_KPI_Update_ProductionDay_Output
		(
			 ProductionDay_pdId		INT
			,ProductionDay_pdDate	DATE
			,isWeekend				BIT
			,isHoliday				BIT
			,isMovedWorkday			BIT
			,isMovedRestday			BIT
		)

	END

	-- szükséges adatok másolása változókba
	DECLARE  @updateDateTime			DATETIME
			,@selectedMeasurePointId	INT
			,@nowDateTime				DATETIME
			,@ProductionDay_pdId		INT
			,@ProductionDay_pdDate		DATE
			,@isWeekend					BIT
			,@isHoliday					BIT
			,@isMovedWorkday			BIT
			,@isMovedRestday			BIT

	-- ez a mérési pont
	DECLARE @thisMeasurePointId INT = 1 -- Salvagnini

	-- adatok változókba olvasása
	SELECT
		 @updateDateTime = updateDateTime
		,@selectedMeasurePointId = selectedMeasurePointId
		,@nowDateTime = nowDateTime
	FROM
		#startupParameters

	SELECT
		 @ProductionDay_pdId = ProductionDay_pdId
		,@ProductionDay_pdDate = ProductionDay_pdDate
		,@isWeekend = isWeekend
		,@isHoliday = isHoliday
		,@isMovedWorkday = isMovedWorkday
		,@isMovedRestday = isMovedRestday
	FROM
		#SP_KPI_Update_ProductionDay_Output

	-- ha nem kell frissíteni ezt a mérési pontot akkor kilépés
	IF @selectedMeasurePointId IS NOT NULL
	   AND @selectedMeasurePointId != @thisMeasurePointId
		RETURN

	-- műszak kezdetének és végének meghatározása
	DECLARE @temp0 TABLE
	(
		 ProductionMeasurePoint_pmpId					INT
		,ShiftSchedule_ssId								INT
		,ProductionMeasurePoint_pmpShiftScheduleRange	INT
		,ShiftScheduleRange_ssrIsPlannedProduction		BIT
		,shiftBegins									DATETIME
		,shiftEnds										DATETIME
	)

	-- a mérési ponthoz hozzárendelt műszak keresése
	INSERT INTO @temp0
	(
		 ProductionMeasurePoint_pmpId
		,ShiftSchedule_ssId
		,ProductionMeasurePoint_pmpShiftScheduleRange
		,ShiftScheduleRange_ssrIsPlannedProduction
	)
	SELECT
		 pmpId
		,ssId
		,pmpShiftScheduleRange
		,ssrIsPlannedProduction
	FROM
		WitturToolsProd.dbo.ProductionMeasurePoint
		INNER JOIN WitturToolsProd.dbo.ShiftScheduleRange ON ssrId = pmpShiftScheduleRange
		INNER JOIN WitturToolsProd.dbo.ShiftSchedule ON ssId = ssrShiftSchedule
	WHERE
		pmpProductionDay = @ProductionDay_pdId
		AND pmpMeasurePoint = @thisMeasurePointId

	-- ha nincs hozzárendelt műszak akkor kilépés
	IF NOT EXISTS
	(
		SELECT
			1
		FROM
			@temp0
	)
		RETURN

	-- debug
	--SELECT * FROM @temp0

	-- műszak kezdetének meghatározása
	UPDATE
		@temp0
	SET
		shiftBegins = 
		(
			SELECT
				DATETIMEFROMPARTS
				(
					 DATEPART(YEAR, @ProductionDay_pdDate)
					,DATEPART(MONTH, @ProductionDay_pdDate)
					,DATEPART(DAY, @ProductionDay_pdDate)
					,srBeginsHours
					,0
					,0
					,0
				)
			FROM
				WitturToolsProd.dbo.ShiftScheduleRange
				INNER JOIN WitturToolsProd.dbo.ShiftRange ON srId = ssrShiftRange
			WHERE
				ssrId = ProductionMeasurePoint_pmpShiftScheduleRange
		)

	-- debug
	--SELECT * FROM @temp0

	-- műszak végének meghatározása
	UPDATE
		@temp0
	SET
		shiftEnds = 
		(
			SELECT
				DATEADD
				(
					 DAY
					,srEndsDay
					,DATETIMEFROMPARTS
					 (
						 DATEPART(YEAR, @ProductionDay_pdDate)
						,DATEPART(MONTH, @ProductionDay_pdDate)
						,DATEPART(DAY, @ProductionDay_pdDate)
						,srEndsHours
						,0
						,0
						,0
					 )
				)
			FROM
				WitturToolsProd.dbo.ShiftScheduleRange
				INNER JOIN WitturToolsProd.dbo.ShiftRange ON srId = ssrShiftRange
			WHERE
				ssrId = ProductionMeasurePoint_pmpShiftScheduleRange
		)

	-- debug
	--SELECT * FROM @temp0

	-- műszak kiválasztása
	DELETE @temp0
	WHERE NOT (@updateDateTime > shiftBegins AND @updateDateTime <= shiftEnds)

	-- debug
	--SELECT * FROM @temp0

	DECLARE  @ProductionMeasurePoint_pmpId					INT
			,@ShiftSchedule_ssId							INT
			,@ShiftScheduleRange_ssrIsPlannedProduction		BIT
			,@shiftBegins									DATETIME
			,@shiftEnds										DATETIME

	SELECT
		 @ProductionMeasurePoint_pmpId = ProductionMeasurePoint_pmpId
		,@ShiftSchedule_ssId = ShiftSchedule_ssId
		,@ShiftScheduleRange_ssrIsPlannedProduction = ShiftScheduleRange_ssrIsPlannedProduction
		,@shiftBegins = shiftBegins
		,@shiftEnds = shiftEnds
	FROM
		@temp0

	-- műszak hosszának számítása
	DECLARE @shiftLengthMinutes INT = DATEDIFF(MINUTE, @shiftBegins, @shiftEnds)

	-- hol járunk most a műszakban?
	DECLARE @minutesFromShiftBegins FLOAT = DATEDIFF(SECOND, @shiftBegins, @nowDateTime) / 60.0

	IF @minutesFromShiftBegins > @shiftLengthMinutes
		SET @minutesFromShiftBegins = @shiftLengthMinutes
	
	DECLARE @shiftPercentage FLOAT = @minutesFromShiftBegins / @shiftLengthMinutes

	-- van bejelentkezés a műszakban?
	DECLARE @isLoginExists INT = IIF(EXISTS(
										SELECT
											1
										FROM
											PTS.dbo.Logins WITH (READPAST)
										WHERE
											logWorkplace IN(
																 52		-- Salvagnini Teríték Címkéző
																,1076	-- Salva hajlító
														   )
											AND logLogin BETWEEN @shiftBegins AND @shiftEnds
								   ), 1, 0)

	-- Debug
	--SET @isLoginExists = 1

	-- Debug
	--SELECT
	--	 @ProductionDay_pdDate [frissítendő nap]
	--	,@isWeekend [hétvége?]
	--	,@isHoliday [ünnep?]
	--	,@isMovedWorkday [áth. munkanap?]
	--	,@isMovedRestday [áth. munkaszüneti nap?]
	--	,@ProductionMeasurePoint_pmpId [mérési pont és műszak id]
	--	,@ShiftScheduleRange_ssrIsPlannedProduction [műszakrend szerint tervezett a termelés?]
	--	,@shiftBegins [műszak kezdete]
	--	,@shiftEnds [műszak vége]
	--	,@shiftLengthMinutes [műszak hossz percben]
	--	,@isLoginExists [van bejelentkezés a műszakban?]

	-- Waterfall adat generálás helye
	DECLARE @productionWaterfallTemp TABLE
	(
		 productionMeasurePoint INT
		,waterfallEntry INT
		,timeMinutes FLOAT
		,positionLetter VARCHAR(2)
		,rowNumber INT
		,offset FLOAT
	)

	-- részeredmény tároló
	DECLARE @sumOfTimeMinutes FLOAT

	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: A -> Teljes idő hozzáadása
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,1 -- Teljes idő
		,@shiftLengthMinutes * @shiftPercentage

	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: AB -> Pihenőnap
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,4 -- Pihenőnap
		,-@shiftLengthMinutes * @shiftPercentage
	WHERE
		@ShiftSchedule_ssId IN
		(
			 1	-- 5+2, 3 műszak
			,2	-- 5+2, 2 műszak
			,3	-- 5+2, 1 műszak
		)								-- ha ez a műszakrend van
		AND @isWeekend = 1				-- hétvége van

	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: AB -> Áthelyezett pihenőnap
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,3 -- Áthelyezett pihenőnap
		,-@shiftLengthMinutes * @shiftPercentage
	WHERE
		@ShiftSchedule_ssId IN
		(
			 1	-- 5+2, 3 műszak
			,2	-- 5+2, 2 műszak
			,3	-- 5+2, 1 műszak
		)								-- ha ez a műszakrend van
		AND 
		(
			@isWeekend = 0				-- nincs hétvége
			AND @isMovedRestday = 1		-- és áthelyezett pihenőnap van
		)

	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: AB -> Munkaszüneti nap
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,2 -- Munkaszüneti nap
		,-@shiftLengthMinutes * @shiftPercentage
	WHERE
		@ShiftSchedule_ssId IN
		(
			 1	-- 5+2, 3 műszak
			,2	-- 5+2, 2 műszak
			,3	-- 5+2, 1 műszak
		)								-- ha ez a műszakrend van
		AND 
		(
			@isWeekend = 0				-- nincs hétvége
			AND @isHoliday = 1			-- és munkaszünati nap van
		)

	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: AB -> Áthelyezett munkanap
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,7 -- Áthelyezett munkanap
		,@shiftLengthMinutes * @shiftPercentage
	WHERE
		@ShiftSchedule_ssId IN
		(
			 1	-- 5+2, 3 műszak
			,2	-- 5+2, 2 műszak
			,3	-- 5+2, 1 műszak
		)								-- ha ez a műszakrend van
		AND 
		(
			@isWeekend = 1				-- ha hétvége van
			AND @isMovedWorkday = 1		-- és áthelyezett munkanap van
		)


	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: AB -> Nincs műszak
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,5 -- Nincs műszak
		,-@shiftLengthMinutes * @shiftPercentage
	WHERE
		(
			(
				@ShiftSchedule_ssId IN
				(
					 1	-- 5+2, 3 műszak
					,2	-- 5+2, 2 műszak
					,3	-- 5+2, 1 műszak
				)											-- ha ez a műszakrend van
				AND 
				(
					@isWeekend = 0							-- ha nincs hétvége
					OR
					(
						@isWeekend = 1						-- ha hétvége van
						AND @isMovedWorkday = 1				-- és áthelyezett munkanap van
					)
				)
				AND @isMovedRestday = 0						-- és nincs áthelyezett pihenőnap
				AND @isHoliday = 0							-- és nincs munkaszüneti nap
			)
			OR 
			(
				@ShiftSchedule_ssId NOT IN
				(
					 1	-- 5+2, 3 műszak
					,2	-- 5+2, 2 műszak
					,3	-- 5+2, 1 műszak
				)											-- ha nem ez a műszakrend van
			)
		)
		AND @ShiftScheduleRange_ssrIsPlannedProduction = 0	-- és nincs műszak

	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: AB -> Túlóra
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,9 -- Túlóra
		,@shiftLengthMinutes * @shiftPercentage
	WHERE
		@isLoginExists = 1														-- ha van bejelentkezés
		AND
		(
			@ShiftSchedule_ssId IN
			(
				 1	-- 5+2, 3 műszak
				,2	-- 5+2, 2 műszak
				,3	-- 5+2, 1 műszak
			)																	-- ha ez a műszakrend van
			AND 
			(
				(
					@isWeekend = 1												-- ha hétvége van
					AND
					(
						@isMovedWorkday = 0										-- ha nincs áthelyezett munkanap
						OR
						(
							@isMovedWorkday = 1									-- ha áthelyezett munkanap van
							AND @ShiftScheduleRange_ssrIsPlannedProduction = 0	-- és nincs műszak
						)
					)
				)
				OR
				(
					@isWeekend = 0												-- ha nincs hétvége
					AND
					(
						@isHoliday = 1											-- ha munkaszünati nap van
						OR @isMovedRestday = 1									-- vagy áthelyezett pihenőnap van
						OR @ShiftScheduleRange_ssrIsPlannedProduction = 0		-- vagy nincs műszak
					)
				)
			)
		)
	
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: AB -> Tervezett szünet
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- részösszeg számítás
	SELECT
		@sumOfTimeMinutes = SUM(timeMinutes)
	FROM
		@productionWaterfallTemp
		INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = waterfallEntry
		INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
	WHERE
		wepPositionLetter IN('A', 'AB')

	-- ha lesz munka ebben a műszakban akkor szünetet adunk hozzá
	DECLARE @plannedBreak FLOAT = CASE
									WHEN @shiftLengthMinutes = 480 THEN -30 * @shiftPercentage
									WHEN @shiftLengthMinutes = 720 THEN -45 * @shiftPercentage
									ELSE 0
								  END

	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,11 -- Tervezett szünet
		,@plannedBreak
	WHERE
		@sumOfTimeMinutes != 0

	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Csomópont: B -> Rendelkezésre állási idő
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- részösszeg számítás
	SELECT
		@sumOfTimeMinutes = SUM(timeMinutes)
	FROM
		@productionWaterfallTemp
		INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = waterfallEntry
		INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
	WHERE
		wepPositionLetter IN('A', 'AB')

	INSERT INTO @productionWaterfallTemp
	(
		 productionMeasurePoint
		,waterfallEntry
		,timeMinutes
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,12 -- Rendelkezésre állási idő
		,@sumOfTimeMinutes

	-- ha nem nulla a rendelkezésre állási idő csak akkor van értelme tovább menni
	IF @sumOfTimeMinutes != 0
	BEGIN
		
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- Mérési pont használat detektálás
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- pts adatok gyűjtése ide
		DECLARE @ptsLogTemp TABLE
		(
			logId INT,
			logWorkplace INT,
			logIn DATETIME,
			logOut DATETIME
		)

		-- pts adatok gyűjtése
		INSERT INTO @ptsLogTemp
		SELECT
			logid,
			logWorkplace,
			logLogin,
			logLogOut
		FROM
			PTS.dbo.Logins WITH (READPAST)
		WHERE
			logWorkplace IN(52, 1076)
			AND logLogin BETWEEN @shiftBegins AND @shiftEnds
		ORDER BY
			logLogin

		-- ha még aktív a bejelentkezés
		UPDATE
			d
		SET
			logOut = @nowDateTime
		FROM
			@ptsLogTemp d
		WHERE
			logOut IS NULL

		-- pts adatok javítása
		UPDATE
			d
		SET
			logOut = @shiftEnds
		FROM
			@ptsLogTemp d
		WHERE
			logOut > @shiftEnds

		-- debug
		--SELECT * FROM @ptsLogTemp	

		-- események gyűjtése ide
		DECLARE @productionActivity TABLE
		(
			occurredWhen DATETIME,
			occurredWhere INT
		)

		-- események gyűjtése
		INSERT INTO @productionActivity
		(
			occurredWhen,
			occurredWhere
		)
		SELECT
			logIn,
			logWorkplace
		FROM
			@ptsLogTemp

		INSERT INTO @productionActivity
		(
			occurredWhen,
			occurredWhere
		)
		SELECT
			logOut,
			logWorkplace
		FROM
			@ptsLogTemp

		-- Debug
		--SELECT * FROM @productionActivity

		-- indexelt események gyűjtése ide
		DECLARE @indexedProductionActivity TABLE
		(
			 productionMeasurePoint INT
			,[index] INT
			,occurredWhen DATETIME
			,occurredWhere INT
			,occurredWhat INT
			,operation INT
			,downtimeSourceWorkplaceId INT
			,productSourceWorkplaceId INT
			,ends DATETIME
			,lengthMinutes FLOAT
			,downtimeIdThatStoppedByLogoutNoActivity	INT
			,scannedDowntimeCount INT
			,scannedProductCount INT
			,downtimeIdToBeAdded INT
			,productionActivity INT
		);

		-- sorszámozás
		INSERT INTO @indexedProductionActivity
		(
			productionMeasurePoint,
			[index],
			occurredWhen,
			occurredWhere
		)
		SELECT
			@ProductionMeasurePoint_pmpId,
			ROW_NUMBER() OVER (ORDER BY occurredWhen ASC, occurredWhere ASC) AS [index],
			occurredWhen,
			occurredWhere
		FROM
			@productionActivity

		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]

		-- mi volt az esemény
		UPDATE
			d
		SET
			occurredWhat =
			(
				CASE
					WHEN EXISTS
					(
						SELECT
							1
						FROM
							@ptsLogTemp
						WHERE
							d.occurredWhen = logIn
							AND d.occurredWhere = logWorkplace
					) THEN 2 -- Bejelentkezés
					WHEN EXISTS
					(
						SELECT
							1
						FROM
							@ptsLogTemp
						WHERE
							d.occurredWhen = logOut
							AND d.occurredWhere = logWorkplace
					) THEN 1 -- Kijelentkezés
				END
			)
		FROM
			@indexedProductionActivity d

		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]

		-- művelet detektálás
		-- ciklus segédváltozók
		DECLARE @currentIndex DATETIME =
		(
			SELECT
				MIN([index])
			FROM
				@indexedProductionActivity
		)

		DECLARE @cuttingLoggedIn BIT = 0
		DECLARE @bendingLoggedIn BIT = 0

		WHILE @currentIndex IS NOT NULL
		BEGIN

			-- művelet frissítése
			UPDATE
				d
			SET
				operation =
				(
					CASE
						WHEN @cuttingLoggedIn = 0 AND @bendingLoggedIn = 0 AND occurredWhere = 52   AND occurredWhat = 2 THEN 1 -- Kivágás
						WHEN @cuttingLoggedIn = 0 AND @bendingLoggedIn = 0 AND occurredWhere = 1076 AND occurredWhat = 2 THEN 2 -- Élhajlítás
						WHEN @cuttingLoggedIn = 0 AND @bendingLoggedIn = 1 AND occurredWhere = 52   AND occurredWhat = 2 THEN 6 -- Kivágás és élhajlítás
						WHEN @cuttingLoggedIn = 0 AND @bendingLoggedIn = 1 AND occurredWhere = 1076 AND occurredWhat = 1 THEN 7 -- Nincs aktivitás
						WHEN @cuttingLoggedIn = 1 AND @bendingLoggedIn = 1 AND occurredWhere = 52   AND occurredWhat = 1 THEN 2 -- Élhajlítás
						WHEN @cuttingLoggedIn = 1 AND @bendingLoggedIn = 1 AND occurredWhere = 1076 AND occurredWhat = 1 THEN 1 -- Kivágás
						WHEN @cuttingLoggedIn = 1 AND @bendingLoggedIn = 0 AND occurredWhere = 52   AND occurredWhat = 1 THEN 7 -- Nincs aktivitás
						WHEN @cuttingLoggedIn = 1 AND @bendingLoggedIn = 0 AND occurredWhere = 1076 AND occurredWhat = 2 THEN 6 -- Kivágás és élhajlítás
					END
				)
			FROM
				@indexedProductionActivity d
			WHERE
				[index] = @currentIndex

			-- ha nem sikerült frissíteni a műveletet akkor kilépünk a ciklusból
			/*IF (SELECT operation FROM @indexedProductionActivity WHERE [index] = @currentIndex) IS NULL
			BEGIN
				SELECT @cuttingLoggedIn, @bendingLoggedIn
				BREAK
			END*/

			-- bejelentkezési állapotok tárolása a következő ciklushoz
			SET @cuttingLoggedIn =
			(
				CASE
					WHEN EXISTS (SELECT 1 FROM @indexedProductionActivity WHERE [index] = @currentIndex AND occurredWhere = 52 AND occurredWhat = 2) THEN 1
					WHEN EXISTS (SELECT 1 FROM @indexedProductionActivity WHERE [index] = @currentIndex AND occurredWhere = 52 AND occurredWhat = 1) THEN 0
					ELSE @cuttingLoggedIn
				END
			)

			SET @bendingLoggedIn =
			(
				CASE
					WHEN EXISTS (SELECT 1 FROM @indexedProductionActivity WHERE [index] = @currentIndex AND occurredWhere = 1076 AND occurredWhat = 2) THEN 1
					WHEN EXISTS (SELECT 1 FROM @indexedProductionActivity WHERE [index] = @currentIndex AND occurredWhere = 1076 AND occurredWhat = 1) THEN 0
					ELSE @bendingLoggedIn
				END
			)

			-- ciklus léptetés
			SET @currentIndex =
			(
				SELECT
					MIN([index])
				FROM
					@indexedProductionActivity
				WHERE
					@currentIndex < [index]
			)

		END

		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]

		-- műszakkezdés hozzáadása ha nincs
		INSERT INTO @indexedProductionActivity
		(
			 productionMeasurePoint
			,[index]
			,occurredWhen
			,occurredWhat
			,operation
		)
		SELECT
			 @ProductionMeasurePoint_pmpId
			,0
			,@shiftBegins
			,1	-- Kijelentkezés
			,7   -- Nincs aktivitás
		WHERE
			NOT EXISTS
			(
				SELECT
					1
				FROM
					@indexedProductionActivity
				WHERE
					occurredWhen = @shiftBegins
			)

		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]

		-- műszakvége törlése ha van
		DELETE
			@indexedProductionActivity
		WHERE
			occurredWhen = @shiftEnds

		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]

		-- től-ig és hossz meghatározása
		UPDATE
				d
			SET
				ends = 
				(
					SELECT
						s.occurredWhen
					FROM
						@indexedProductionActivity s
					WHERE
						s.[index] = d.[index] + 1
				)
			FROM
				@indexedProductionActivity d

		UPDATE
			d
		SET
			ends = CASE
						WHEN @nowDateTime BETWEEN @shiftBegins AND @shiftEnds THEN @nowDateTime
						ELSE @shiftEnds
				   END
		FROM
			@indexedProductionActivity d
		WHERE
			ends IS NULL

		UPDATE
			@indexedProductionActivity
		SET
			lengthMinutes = DATEDIFF(SECOND, occurredWhen, ends) / 60.0

		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]

		-- ami még nem történt meg azt töröljük
		DELETE
			@indexedProductionActivity
		WHERE
			ends > @nowDateTime

		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]
		
		-- Kibővített debug
		--SELECT
		--	 [index]
		--	,occurredWhen
		--	,wplDescLoc [occurredWhere]
		--	,weDescriptionHu [occurredWhat]
		--	,odHu [operation]
		--	,begins
		--	,ends
		--	,lengthMinutes
		--FROM @indexedProductionActivity
		--LEFT JOIN PTS.dbo.Workplace ON wplId = occurredWhere
		--LEFT JOIN WitturToolsProd.dbo.WorkplaceEvent ON weId = occurredWhat
		--LEFT JOIN WitturToolsProd.dbo.OperationDescription ON odId = operation
		--ORDER BY [index]

		-- milyen állásidő szűnt meg?
		UPDATE
			t
		SET
			t.downtimeIdThatStoppedByLogoutNoActivity =
			(
				SELECT
					ldtDowntime
				FROM
					PTS.dbo.Logins_Downtime WITH (READPAST)
					INNER JOIN PTS.dbo.Logins WITH (READPAST) ON logid = ldtLogin
												 AND logWorkplace = occurredWhere
												 AND logLogOut = occurredWhen
				WHERE
					ldtEndDatetime BETWEEN DATEADD(SECOND, -1, logLogOut) AND DATEADD(SECOND, 1, logLogOut) -- +/- 1 másodperc
			)
		FROM
			@indexedProductionActivity t
		WHERE
			t.operation = 7 -- Nincs aktivitás 
			AND t.[index] != 0

		-- adatforrások meghatározása
		UPDATE
			t
		SET
			 downtimeSourceWorkplaceId =
			(
				CASE
					WHEN operation = 1 THEN 52		-- ha csak a kivágó munkahelyen van bejelentkezés, az M052-ről olvassuk az állásidőket
					WHEN operation = 2 THEN 1076	-- ha csak az élhajlító munkahelyen van bejelentkezés, az M0363-ről olvassuk az állásidőket
					WHEN operation = 6 THEN 52		-- ha mind két munkahelyen van bejelentkezés, az M052-ről olvassuk az állásidőket
					ELSE NULL
				END
			)
			,productSourceWorkplaceId =
			(
				CASE
					WHEN operation = 1 THEN 52		-- ha csak a kivágó munkahelyen van bejelentkezés, az M052-ről olvassuk a termék komponens szkenneléseket
					WHEN operation = 2 THEN 1076	-- ha csak az élhajlító munkahelyen van bejelentkezés, az M0363-ről olvassuk a termék komponens szkenneléseket
					WHEN operation = 6 THEN 52		-- ha mind két munkahelyen van bejelentkezés, az M052-ről olvassuk a termék komponens szkenneléseket
					ELSE NULL
				END
			)
		FROM
			@indexedProductionActivity t

		-- aktivitáson belüli szkennelések
		UPDATE
			@indexedProductionActivity
		SET
			 scannedDowntimeCount = 0
			,scannedProductCount = 0

		-- volt az aktivitáson belül állásidő szkennelés?
		UPDATE
			t
		SET
			t.scannedDowntimeCount =
			(
				SELECT
					COUNT(ldtid)
				FROM
					PTS.dbo.Logins_Downtime WITH (READPAST)
					INNER JOIN PTS.dbo.Logins WITH (READPAST) ON logid = ldtLogin
				WHERE
					logWorkplace = downtimeSourceWorkplaceId
					AND ldtStartDatetime BETWEEN occurredWhen AND ends
					AND ldtDowntime != 24 -- és nem Tétlenség
			)
		FROM
			@indexedProductionActivity t
		WHERE
			operation != 7 -- ha a művelet nem Nincs aktivitás

		-- volt az aktivitáson belül termék szkennelés?
		UPDATE
			t
		SET
			t.scannedProductCount =
			(
				SELECT
					COUNT(ptrId)
				FROM
					PTS.dbo.ProductTracking WITH (READPAST)
					INNER JOIN PTS.dbo.Logins WITH (READPAST) ON logid = ptrLogin
				WHERE
					logWorkplace = productSourceWorkplaceId
					AND ptrDate BETWEEN occurredWhen AND ends
			)
		FROM
			@indexedProductionActivity t
		WHERE
			operation != 7 -- ha a művelet nem Nincs aktivitás

		-- állásidők beállítása a Nincs aktivitás helyére
		UPDATE
			t
		SET
			downtimeIdToBeAdded =
			(
				CASE
					WHEN downtimeIdThatStoppedByLogoutNoActivity IN
					(
						-- Tervezettek
						 4	-- Leltár
						,17 -- Tervezett tréning
						,21	-- Egyéb (tervezett)
						,37	-- 5S aktivitás
						,69	-- Tervezett karbantartás
						,89	-- Szerszám köszörülés
						,92	-- Nincs megrendelés

						-- Nem tervezettek
						,2	-- Géphiba
						,3	-- Anyaghiány
						,6	-- Tároló mozgatás
						,28	-- Selejtezés
						,34	-- Géphiba elhárítva - nem tervezett
						,36	-- Tároló átpakolás
						,47	-- IT gépállás
						,62	-- Tárolóhiány
						,67 -- Alapanyagra várakozás
						,70	-- Hulladék tároló ürítés

					) THEN downtimeIdThatStoppedByLogoutNoActivity
					ELSE 21 -- Egyéb (tervezett)
				END
			)
		FROM
			@indexedProductionActivity t
		WHERE
			operation = 7 -- Nincs aktivitás

		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- adatmentés / frissítés -> WitturToolsProd.dbo.ProductionActivity
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]
		
		-- Kibővített debug
		--SELECT
		--	 [index]
		--	,occurredWhen
		--	,wplDescLoc [occurredWhere]
		--	,weDescriptionHu [occurredWhat]
		--	,odHu [operation]
		--	,begins
		--	,ends
		--	,lengthMinutes
		--	,ISNULL(dwt0.dwtDescLoc, '-') [downtimeIdThatStoppedByLogoutNoActivity]
		--	,scannedDowntimeCount
		--	,scannedProductCount
		--	,ISNULL(dwt1.dwtDescLoc, '-') [downtimeIdToBeAdded]
		--FROM @indexedProductionActivity
		--LEFT JOIN PTS.dbo.Workplace ON wplId = occurredWhere
		--LEFT JOIN PTS.dbo.Downtime dwt0 ON dwt0.dwtid = downtimeIdThatStoppedByLogoutNoActivity
		--LEFT JOIN WitturToolsProd.dbo.WorkplaceEvent ON weId = occurredWhat
		--LEFT JOIN WitturToolsProd.dbo.OperationDescription ON odId = operation
		--LEFT JOIN PTS.dbo.Downtime dwt1 ON dwt1.dwtid = downtimeIdToBeAdded
		--ORDER BY [index]

		----------------
		MERGE INTO 
			WitturToolsProd.dbo.ProductionActivity t
		USING 
			@indexedProductionActivity s
		ON 
			t.paProductionMeasurePoint = s.productionMeasurePoint
			AND t.paIndex = s.[index]
		WHEN NOT MATCHED BY TARGET THEN
			INSERT 
			(
				 paProductionMeasurePoint
				,paIndex
				,paOccurredWhen
				,paOccurredWherePTSWorkplace
				,paOccurredWhatWorkplaceEvent
				,paOperationDescription
				,paDowntimeSourcePTSWorkplace
				,paProcductSourcePTSWorkplace
				,paEnds
				,paLengthMinutes
				,paPTSDowntimeThatStoppedByLogoutNoActivity
				,paScannedDowntimeCount
				,paScannedProductCount
				,paPTSDowntimeToBeAdded
			)
			VALUES 
			(
				 s.productionMeasurePoint
				,s.[index]
				,s.occurredWhen
				,s.occurredWhere
				,s.occurredWhat
				,s.operation
				,s.downtimeSourceWorkplaceId
				,s.productSourceWorkplaceId
				,s.ends
				,s.lengthMinutes
				,s.downtimeIdThatStoppedByLogoutNoActivity
				,s.scannedDowntimeCount
				,s.scannedProductCount
				,s.downtimeIdToBeAdded
			)
		WHEN MATCHED AND t.paEnds != s.ends THEN
			UPDATE SET
				 t.paEnds = s.ends
				,t.paLengthMinutes = s.lengthMinutes
				,t.paPTSDowntimeThatStoppedByLogoutNoActivity = s.downtimeIdThatStoppedByLogoutNoActivity
				,t.paScannedDowntimeCount = s.scannedDowntimeCount
				,t.paScannedProductCount = s.scannedProductCount
				,t.paPTSDowntimeToBeAdded = s.downtimeIdToBeAdded;

		-- Debug
		--SELECT * FROM WitturToolsProd.dbo.ProductionActivity ORDER BY [paIndex]

		-- id visszaolvasása
		UPDATE
			t
		SET
			t.productionActivity = s.paId
		FROM
			@indexedProductionActivity t
			INNER JOIN WitturToolsProd.dbo.ProductionActivity s ON s.paProductionMeasurePoint = t.productionMeasurePoint
																   AND s.paIndex = t.[index]
																   AND s.paOccurredWhen = t.occurredWhen
																   AND (
																		s.paOccurredWherePTSWorkplace = t.occurredWhere
																		OR (
																				s.paOccurredWherePTSWorkplace IS NULL
																				AND t.occurredWhere IS NULL
																		   )
																 	   )
																   AND s.paOccurredWhatWorkplaceEvent = t.occurredWhat
																   AND s.paOperationDescription = t.operation
																   AND (
																		s.paDowntimeSourcePTSWorkplace = t.downtimeSourceWorkplaceId
																		OR (
																				s.paDowntimeSourcePTSWorkplace IS NULL
																				AND t.downtimeSourceWorkplaceId IS NULL
																		   )
																	   )
																   AND (
																		s.paProcductSourcePTSWorkplace = t.productSourceWorkplaceId
																		OR (
																				s.paProcductSourcePTSWorkplace IS NULL
																				AND t.productSourceWorkplaceId IS NULL
																		   )
																	   )

		-- Debug
		--SELECT * FROM @indexedProductionActivity ORDER BY [index]
		
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- Állásidők gyűjtése
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		DECLARE @downtime TABLE
		(
			 productionActivity INT
			,ldtid INT
			,ldtDowntime INT
			,begins DATETIME
			,ends DATETIME
			,isActive BIT
			,lengthMinutes FLOAT
		)
		
		-- adatok gyűjtése a PTS-ből
		INSERT INTO @downtime
		(
			 productionActivity
			,ldtid
			,ldtDowntime
			,begins
			,ends
			,isActive
		)
		SELECT
			 productionActivity
			,ldtid
			,ldtDowntime
			,ldtStartDatetime
			,ISNULL(ldtEndDatetime, @nowDateTime)
			,IIF(ldtEndDatetime IS NULL, 1, 0)
		FROM
			@indexedProductionActivity ipa
			INNER JOIN PTS.dbo.Logins WITH (READPAST) ON logWorkplace = downtimeSourceWorkplaceId
			INNER JOIN PTS.dbo.Logins_Downtime WITH (READPAST) ON ldtLogin = logid
		WHERE
			scannedDowntimeCount != 0
			AND ldtStartDatetime BETWEEN occurredWhen AND ends
			AND ldtDowntime != 24 -- és nem Tétlenség

		-- állásidő végének javítása
		UPDATE
			t
		SET
			t.ends = IIF(t.ends > s.ends, s.ends, t.ends) -- az állásidő vége nem nyúlhat túl az aktivitás végén
		FROM
			@downtime t
			INNER JOIN @indexedProductionActivity s ON s.productionActivity = t.productionActivity

		-- automatikus ill. hosszabbított állásidők hozzáadása
		INSERT INTO @downtime
		(
			 productionActivity
			,ldtDowntime
			,begins
			,ends
			,isActive
		)
		SELECT
			 productionActivity
			,downtimeIdToBeAdded
			,occurredWhen
			,ends
			,IIF(@nowdatetime BETWEEN occurredWhen AND ends, 1, 0)
		FROM
			@indexedProductionActivity
		WHERE
			downtimeIdToBeAdded IS NOT NULL

		-- állásidő hosszának kiszámítása
		UPDATE
			t
		SET
			t.lengthMinutes = DATEDIFF(SECOND, begins, ends) / 60.0
		FROM
			@downtime t

		-- ha az állásidő hossza null akkor törlés
		DELETE
			@downtime
		WHERE
			lengthMinutes = 0

		-- nem megfelelő PTS használat miatti sikertelen aktivitás összerendelés
		-- TODO: további vizsgálatot igényel
		DELETE
			@downtime
		WHERE
			productionActivity IS NULL

		-- állásidők csökkentése a szünet hosszával
		DECLARE @sumOfDowntimeMinutes FLOAT = 
		(
			SELECT
				SUM(lengthMinutes)
			FROM
				@downtime
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON wePTSDowntime = ldtDowntime
			WHERE
				weWaterfallEntryPosition IN
				(
					 4	-- BC
					,6	-- CD
				)
		)

		DECLARE @downtimeMinutesDecreaseValuePerMinute FLOAT = @plannedBreak / @sumOfDowntimeMinutes

		UPDATE
			t
		SET
			t.lengthMinutes += t.lengthMinutes * @downtimeMinutesDecreaseValuePerMinute
		FROM
			@downtime t
			INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON wePTSDowntime = ldtDowntime
		WHERE
			weWaterfallEntryPosition IN
			(
				 4	-- BC
				,6	-- CD
			)

		-- debug
		--SELECT * FROM @downtime
		
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- adatmentés / frissítés -> WitturToolsProd.dbo.ProductionDowntime
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		MERGE INTO 
			WitturToolsProd.dbo.ProductionDowntime t
		USING 
			@downtime s
		ON 
			t.pdProductionActivity = s.productionActivity
			AND (
					t.pdPTSLoginsDowntime = s.ldtid
					OR (
							t.pdPTSLoginsDowntime IS NULL
							AND s.ldtid IS NULL
					   )
				)
			AND t.pdPTSDowntime = s.ldtDowntime
			AND t.pdBegins = s.begins
		WHEN NOT MATCHED BY TARGET THEN
			INSERT 
			(
				 pdProductionActivity
				,pdPTSLoginsDowntime
				,pdPTSDowntime
				,pdBegins
				,pdEnds
				,pdIsActive
				,pdLengthMinutes
			)
			VALUES 
			(
				 s.productionActivity
				,s.ldtid
				,s.ldtDowntime
				,s.begins
				,s.ends
				,s.isActive
				,s.lengthMinutes
			)
		WHEN MATCHED THEN
			UPDATE SET
				 t.pdEnds = s.ends
				,t.pdIsActive = s.isActive
				,t.pdLengthMinutes = s.lengthMinutes;

		-- debug
		--SELECT * FROM WitturToolsProd.dbo.ProductionDowntime

		-- aktív állásidő flag törlése az előző műszakokból ha van beragadva vagy van nem beállított
		UPDATE
			t
		SET
			t.pdIsActive = 0
		FROM
			WitturToolsProd.dbo.ProductionMeasurePoint
			INNER JOIN WitturToolsProd.dbo.ProductionActivity ON paProductionMeasurePoint = pmpId
			INNER JOIN WitturToolsProd.dbo.ProductionDowntime t ON pdProductionActivity = paId
		WHERE
			pmpMeasurePoint = @thisMeasurePointId
			AND pmpId != @ProductionMeasurePoint_pmpId
			AND pdIsActive = 1

		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- Csomópontok: BC
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		INSERT INTO @productionWaterfallTemp
		(
			 productionMeasurePoint
			,waterfallEntry
			,timeMinutes
		)
		SELECT
			 @ProductionMeasurePoint_pmpId
			,weId
			,-SUM(lengthMinutes)
		FROM
			@downtime
			INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON wePTSDowntime = ldtDowntime
		WHERE
			weWaterfallEntryPosition = 4	-- BC
		GROUP BY
			weId

		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- Csomópont: C -> Ütemzett idő
		------------------------------------------------------------------------------------------------------------------------------------------------------------
		-- részösszeg számítás
		SELECT
			@sumOfTimeMinutes = SUM(timeMinutes)
		FROM
			@productionWaterfallTemp
			INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = waterfallEntry
			INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
		WHERE
			wepPositionLetter IN('B', 'BC')

		INSERT INTO @productionWaterfallTemp
		(
			 productionMeasurePoint
			,waterfallEntry
			,timeMinutes
		)
		SELECT
			 @ProductionMeasurePoint_pmpId
			,28 -- Ütemzett idő
			,@sumOfTimeMinutes

		-- ha nem nulla az Ütemzett idő csak akkor van értelme tovább menni
		IF @sumOfTimeMinutes != 0
		BEGIN

			------------------------------------------------------------------------------------------------------------------------------------------------------------
			-- Csomópontok: CD
			------------------------------------------------------------------------------------------------------------------------------------------------------------
			INSERT INTO @productionWaterfallTemp
			(
				 productionMeasurePoint
				,waterfallEntry
				,timeMinutes
			)
			SELECT
				 @ProductionMeasurePoint_pmpId
				,weId
				,CASE
					WHEN @sumOfTimeMinutes >= SUM(lengthMinutes) THEN -SUM(lengthMinutes)
					ELSE -@sumOfTimeMinutes
				END
			FROM
				@downtime
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON wePTSDowntime = ldtDowntime
			WHERE
				weWaterfallEntryPosition = 6	-- CD
			GROUP BY
				weId

			------------------------------------------------------------------------------------------------------------------------------------------------------------
			-- Csomópont: D -> Gyártási idő
			------------------------------------------------------------------------------------------------------------------------------------------------------------
			-- részösszeg számítás
			SELECT
				@sumOfTimeMinutes = SUM(timeMinutes)
			FROM
				@productionWaterfallTemp
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = waterfallEntry
				INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
			WHERE
				wepPositionLetter IN('C', 'CD')

			INSERT INTO @productionWaterfallTemp
			(
				 productionMeasurePoint
				,waterfallEntry
				,timeMinutes
			)
			SELECT
				 @ProductionMeasurePoint_pmpId
				,59 -- Gyártási idő
				,@sumOfTimeMinutes

			-- ha nem nulla a Gyártási idő csak akkor van értelme tovább menni
			IF @sumOfTimeMinutes != 0
			BEGIN

				-- debug
				--SELECT * FROM @indexedProductionActivity

				-- gyártott alkatrészek gyűjtése ide
				DECLARE @product TABLE
				(
					 autoIncrementId INT IDENTITY(1,1) PRIMARY KEY
					,productionActivity INT
					,ptrId INT
					,psId INT
					,productionDowntime INT
					,productionTimeMinutes FLOAT
					,productionTimeAssignmentRule INT
					,productionTimeSource INT
					,downtime INT
					,operation INT
					,scanned DATETIME
					,prio INT
					,[order] INT
					,[mod] INT
					,[drawingNumber] VARCHAR(32)
					,idCode VARCHAR(16)
					,[lv] FLOAT
					,barCode VARCHAR(24)
					,hasSikanBending BIT
					,oneComponentInOneTableProductionTime FLOAT
					,hasSikanBendingTimeMinutes FLOAT
					,uniqueCuttingTimeMinutes FLOAT
				)

				-- gyártott alkatrészek gyűjtése
				INSERT INTO @product
				(
					 productionActivity
					,operation
					,ptrId
				)
				SELECT
					 productionActivity
					,operation
					,ptrId
				FROM
					@indexedProductionActivity
					INNER JOIN PTS.dbo.ProductTracking WITH (READPAST) ON ptrDate BETWEEN occurredWhen AND ends
					INNER JOIN PTS.dbo.Logins WITH (READPAST) ON logid = ptrLogin
				WHERE
					scannedProductCount != 0
					AND logWorkplace = productSourceWorkplaceId
					-- csak azokat a szkenneléseket gyűjtsük össze amelyekhez még nincs időhozzárendelés
					-- vagy nem sikerült időt hozzárendelni, vagy mod átlag időt kaptak
					AND NOT EXISTS
					(
						SELECT
							1
						FROM
							WitturToolsProd.dbo.ProductionProduct
						WHERE
							ppProductionActivity = productionActivity
							AND ppPTSProductTracking = ptrId
							AND ppProductionTimeSource NOT IN
							(
								 6 -- Sikertelen időösszerendelés
								,5 -- Kézi időösszerendelés: Alkatrész csoport átlag
							)
					)

				-- debug
				--SELECT * FROM @product

				-- plusz infók gyűtése az időösszerendeléshez
				UPDATE
					t
				SET
					 scanned = ptrDate
					,prio = pprPrio
					,[order] = poiRend
					,[mod] = prgMOD
					,[drawingNumber] = drvfullname
					,idcode = poiidkod
					,[lv] = poiLV
					,barCode = barBarcode
				FROM
					@product t
					INNER JOIN PTS.dbo.ProductTracking ptr WITH (READPAST) ON ptr.ptrId = t.ptrId
					INNER JOIN PTS.dbo.Product WITH (READPAST) ON prdid = ptrProduct
					INNER JOIN PTS.dbo.ProductOrder WITH (READPAST) ON prdPO = porPO
					INNER JOIN PTS.dbo.ProductOrderIdentity WITH (READPAST) ON porPOIdentity = poiid
					INNER JOIN PTS.dbo.Product_Prio_CO WITH (READPAST) ON poiRend = ppcoCO and poiDocType = ppcoDocType
					INNER JOIN PTS.dbo.Product_Prio WITH (READPAST) ON ppcoPrio = pprID
					INNER JOIN PTS.dbo.DrawingNumber_Version WITH (READPAST) ON poiDrawingNumber_Version = drvid
					INNER JOIN PTS.dbo.DrawingNumber WITH (READPAST) ON drvDrawing = drwid
					INNER JOIN PTS.dbo.ProductGroup WITH (READPAST) ON drwProductGroup = prgid
					INNER JOIN PTS.dbo.BarCode WITH (READPAST) ON barProduct = ptrProduct
				WHERE
					t.ptrId IS NOT NULL

				-- debug
				--SELECT * FROM @product

				-- selejt alkatrészek gyűjtése
				INSERT INTO @product
				(
					 productionActivity
					,operation
					,psId
				)
				SELECT
					 productionActivity
					,operation
					,psId
				FROM
					@indexedProductionActivity
					INNER JOIN WitturToolsProd.dbo.ProductionScrap ON psCreated BETWEEN occurredWhen AND ends
				WHERE
					psMeasurePoint = @thisMeasurePointId
					AND psCause NOT LIKE '%teszt%'
					-- csak azokat a szkenneléseket gyűjtsük össze amelyekhez még nincs időhozzárendelés
					-- vagy nem sikerült időt hozzárendelni, vagy mod átlag időt kaptak
					AND NOT EXISTS
					(
						SELECT
							1
						FROM
							WitturToolsProd.dbo.ProductionProduct
						WHERE
							ppProductionActivity = productionActivity
							AND ppProductionScrap = psId
							AND ppProductionTimeSource NOT IN
							(
								 6 -- Sikertelen időösszerendelés
								,5 -- Kézi időösszerendelés: Alkatrész csoport átlag
							)
					)

				-- plusz infók gyűtése az időösszerendeléshez (selejt)
				UPDATE
					t
				SET
					 scanned = ps.psCreated
					,prio = pprPrio
					,[order] = poiRend
					,[mod] = prgMOD
					,[drawingNumber] = drvfullname
					,idcode = poiidkod
					,[lv] = poiLV
					,barCode = pplBarCode
				FROM
					@product t
					INNER JOIN WitturToolsProd.dbo.ProductionScrap ps ON ps.psId = t.psId
					INNER JOIN PTS.dbo.ProductionOrder_PrintLog WITH (READPAST) ON pplid = psPTSProductionOrderPrintLog
					INNER JOIN PTS.dbo.ProductOrder WITH (READPAST) ON porPO = pplPo
					INNER JOIN PTS.dbo.ProductOrderIdentity WITH (READPAST) ON porPOIdentity = poiid
					INNER JOIN PTS.dbo.Product_Prio_CO WITH (READPAST) ON poiRend = ppcoCO and poiDocType = ppcoDocType
					INNER JOIN PTS.dbo.Product_Prio WITH (READPAST) ON ppcoPrio = pprID
					INNER JOIN PTS.dbo.DrawingNumber_Version WITH (READPAST) ON poiDrawingNumber_Version = drvid
					INNER JOIN PTS.dbo.DrawingNumber WITH (READPAST) ON drvDrawing = drwid
					INNER JOIN PTS.dbo.ProductGroup WITH (READPAST) ON drwProductGroup = prgid
				WHERE
					t.psId IS NOT NULL

				-- debug
				--SELECT * FROM @product

				-- detektáljuk hogy a termékek melyik állásidőben voltak szkennelve
				UPDATE
					t
				SET
					 productionDowntime = pdId
					,downtime = pdPTSDowntime
				FROM
					@product t
					INNER JOIN WitturToolsProd.dbo.ProductionDowntime ON pdProductionActivity = productionActivity
																		 AND scanned BETWEEN pdBegins AND pdEnds

				-- debug
				--SELECT * FROM @product

				------------------------------------------------------------------------------------------------------------------------------------------------------------
				-- időösszerendelések
				------------------------------------------------------------------------------------------------------------------------------------------------------------
				-- Próbagyártás közben szkennelt alkatrészek
				UPDATE
					t
				SET
					  productionTimeMinutes = 0
					 ,productionTimeAssignmentRule = 1 -- Gyártási idő hozzárendelés nem szükséges
					 ,productionTimeSource = 1 -- Próbagyártás alatt
				FROM
					@product t
				WHERE
					downtime = 40 -- Próbagyártás
				
				-- debug
				--SELECT * FROM @product

				-- időösszerendelés - 1 tábla 1 alkatrész
				UPDATE
					t
				SET
					oneComponentInOneTableProductionTime =
					(
						SELECT
							AVG(cmoiioscCuttingTimeMinutes)
						FROM
							[WitturToolsProd].[dbo].[CuttingMachineOneItemInOneSheetCache] WITH (READPAST)
							INNER JOIN WitturToolsProd.dbo.ScheduleDataCacheMachine WITH (READPAST) ON sdcmId = cmoiioscScheduleDataCacheMachine
							INNER JOIN WitturToolsProd.dbo.ScheduleDataCacheMachineProgram WITH (READPAST) ON sdcmpId = cmoiioscScheduleDataCacheMachineProgram
							INNER JOIN PTS.dbo.DrawingNumber_Version WITH (READPAST) ON drvId = cmoiioscProductTrackingSystemDrawingNumberVersion
							INNER JOIN WitturToolsProd.dbo.ProductTrackingSystemCacheIdCode WITH (READPAST) ON ptscicId = cmoiioscProductTrackingSystemCacheIdCode
						WHERE
							cmoiioscPrio = t.prio
							AND cmoiioscOrderNumber = t.[order]
							AND drvfullname = t.drawingNumber
							AND ptscicCode = t.idCode
							AND sdcmName = 'Salvagnini'
					)
				FROM
					@product t
				WHERE
					operation IN
					(
						 1 -- Kivágás
						,6 -- Kivágás és élhajlítás
					)

				-- debug
				--SELECT * FROM @product

				-- ha van az alkatrésznek sikán hajtása
				UPDATE
					d
				SET
					hasSikanBending = IIF(EXISTS
					(
						SELECT
							1
						FROM
							WitturToolsProd.dbo.DrawingNumberHasSikanBending
							INNER JOIN PTS.dbo.DrawingNumber WITH (READPAST) ON drwid = dnhsbPTSDrawingNumber
						WHERE
							drawingNumber LIKE drwname + '%'
					), 1, 0)
				FROM
					@product d

				-- időhozzárendelés a sikán hajtáshoz
				UPDATE
					d
				SET
					hasSikanBendingTimeMinutes = IIF(lv > 1.5, 1.5, 1.0)
				FROM
					@product d
				WHERE
					operation IN
					(
						 2 -- Élhajlítás
						,6 -- Kivágás és élhajlítás
					)
					AND hasSikanBending = 1

				-- debug
				--SELECT * FROM @product

				-- egyedi időhozzárendelés
				DECLARE @currentAutoIncrementId INT =
				(
					SELECT
						MIN(autoIncrementId)
					FROM
						@product
					WHERE
						oneComponentInOneTableProductionTime IS NULL
						AND hasSikanBendingTimeMinutes IS NULL
				)

				DECLARE @currentBarCode VARCHAR(24) =
				(
					SELECT
						barCode
					FROM
						@product
					WHERE
						autoIncrementId = @currentAutoIncrementId
				)

				WHILE @currentAutoIncrementId IS NOT NULL
				BEGIN

					SET @currentBarCode =
					(
						SELECT
							barCode
						FROM
							@product
						WHERE
							autoIncrementId = @currentAutoIncrementId
					)

					DECLARE @result FLOAT
					EXEC WitturToolsProd.dbo.SP_KPI_CuttingMachines_GetUniqueCuttingTimeMinutes @currentBarCode, 'Salvagnini', 0, @result OUT

					UPDATE
						t
					SET
						uniqueCuttingTimeMinutes = ROUND(@result, 3)
					FROM
						@product t
					WHERE
						autoIncrementId = @currentAutoIncrementId

					SET @currentAutoIncrementId =
					(
						SELECT
							MIN(autoIncrementId)
						FROM
							@product
						WHERE
							oneComponentInOneTableProductionTime IS NULL
							AND hasSikanBendingTimeMinutes IS NULL
							AND autoIncrementId > @currentAutoIncrementId
					)

				END

				-- debug
				--SELECT * FROM @product

				-- megvannak az idők, válasszuk ki melyiket használjuk
				UPDATE
					t
				SET
					 productionTimeMinutes = 
					 (
						CASE
							WHEN oneComponentInOneTableProductionTime IS NOT NULL
								 AND hasSikanBendingTimeMinutes IS NULL
								 AND uniqueCuttingTimeMinutes IS NULL THEN oneComponentInOneTableProductionTime
							WHEN oneComponentInOneTableProductionTime IS NULL
								 AND hasSikanBendingTimeMinutes IS NOT NULL
								 AND uniqueCuttingTimeMinutes IS NULL THEN hasSikanBendingTimeMinutes
							WHEN oneComponentInOneTableProductionTime IS NULL
								 AND hasSikanBendingTimeMinutes IS NULL
								 AND uniqueCuttingTimeMinutes IS NOT NULL THEN uniqueCuttingTimeMinutes
						END
					 )
					,productionTimeAssignmentRule = 
					 (
						CASE
							WHEN oneComponentInOneTableProductionTime IS NOT NULL
								 AND hasSikanBendingTimeMinutes IS NULL
								 AND uniqueCuttingTimeMinutes IS NULL THEN 3 -- Géptípus, Művelet, Táblaterv név, Rendelés szám, Teljes rajzszám, Id kód, Egy alkatrész egy táblában
							WHEN oneComponentInOneTableProductionTime IS NULL
								 AND hasSikanBendingTimeMinutes IS NOT NULL
								 AND uniqueCuttingTimeMinutes IS NULL THEN 2 -- Géptípus, Művelet, Rajzszám, Van sikán hajtása
							WHEN oneComponentInOneTableProductionTime IS NULL
								 AND hasSikanBendingTimeMinutes IS NULL
								 AND uniqueCuttingTimeMinutes IS NOT NULL THEN 4 -- Géptípus, Művelet, Táblaterv név, Rendelés szám, Teljes rajzszám, Id kód
						END
					 )
					,productionTimeSource = 
					 (
						CASE
							WHEN oneComponentInOneTableProductionTime IS NOT NULL
								 AND hasSikanBendingTimeMinutes IS NULL
								 AND uniqueCuttingTimeMinutes IS NULL THEN 2 -- Egyedi táblaterv idő CAM programozásból
							WHEN oneComponentInOneTableProductionTime IS NULL
								 AND hasSikanBendingTimeMinutes IS NOT NULL
								 AND uniqueCuttingTimeMinutes IS NULL THEN 4 -- Ha van sikán hajtása és lemezvastagság > 1.5, 1.5, 1
							WHEN oneComponentInOneTableProductionTime IS NULL
								 AND hasSikanBendingTimeMinutes IS NULL
								 AND uniqueCuttingTimeMinutes IS NOT NULL THEN 3 -- Egyedi alkatrész idő CAM programozásból
						END
					 )
				FROM
					@product t

				-- géptípus/mod időösszerendelés
				UPDATE
					t
				SET
					 productionTimeMinutes = 
					 (
						SELECT
							mtmptProductionTimeMinutes
						FROM
							WitturToolsProd.dbo.ProductionActivity
							INNER JOIN WitturToolsProd.dbo.ProductionMeasurePoint ON pmpId = paProductionMeasurePoint
							INNER JOIN WitturToolsProd.dbo.MeasurePoint ON mpId = pmpMeasurePoint
							INNER JOIN WitturToolsProd.dbo.MachineInstance ON miId = mpMachineInstance
							INNER JOIN WitturToolsProd.dbo.MachineType ON mtId = miMachineType
							INNER JOIN WitturToolsProd.dbo.MachineTypeModProductionTime ON mtmptMachineType = mtId
							INNER JOIN PTS.dbo.ProductGroup WITH (READPAST) ON prgId = mtmptPTSProductGroup
							INNER JOIN WitturToolsProd.dbo.Operation ON oId = mtmptOperation
						WHERE
							paId = productionActivity
							AND prgMOD = [mod]
							AND oId = operation
					 )
					,productionTimeAssignmentRule = 5 -- Géptípus, Művelet, Alkatrész csoport
					,productionTimeSource = 5 -- Kézi időösszerendelés: Alkatrész csoport átlag
				FROM
					@product t
				WHERE
					productionTimeMinutes IS NULL

				-- sikertelen időösszerendelés
				UPDATE
					t
				SET
					 productionTimeMinutes = 1
					,productionTimeAssignmentRule = 6 -- -
					,productionTimeSource = 6 -- Sikertelen időösszerendelés
				FROM
					@product t
				WHERE
					productionTimeMinutes IS NULL

				-- nem megfelelő PTS használat miatti sikertelen aktivitás összerendelés
				-- TODO: további vizsgálatot igényel
				DELETE
					@product
				WHERE
					productionActivity IS NULL

				------------------------------------------------------------------------------------------------------------------------------------------------------------
				-- adatmentés -> WitturToolsProd.dbo.ProductionProduct
				------------------------------------------------------------------------------------------------------------------------------------------------------------
				-- debug
				--SELECT * FROM @product

				-- debug
				--PRINT 'debug'

				MERGE INTO 
					WitturToolsProd.dbo.ProductionProduct t
				USING 
					@product s
				ON 
					t.ppProductionActivity = s.productionActivity
					AND 
					(
						(
								(t.ppProductionScrap IS NULL AND s.psId IS NULL)
							AND (t.ppPTSProductTracking IS NOT NULL AND s.ptrId IS NOT NULL)
							AND t.ppPTSProductTracking = s.ptrId
						)
						OR
						(
								(t.ppPTSProductTracking IS NULL AND s.ptrId IS NULL)
							AND (t.ppProductionScrap IS NOT NULL AND s.psId IS NOT NULL)
							AND t.ppProductionScrap = s.psId
						)
					)
				WHEN NOT MATCHED BY TARGET THEN
					INSERT 
					(
						 ppProductionActivity
						,ppPTSProductTracking
						,ppProductionScrap
						,ppProductionDowntime
						,ppProductionTimeMinutes
						,ppProductionTimeAssignmentRule
						,ppProductionTimeSource
					)
					VALUES 
					(
						 productionActivity
						,ptrId
						,psId
						,productionDowntime
						,productionTimeMinutes
						,productionTimeAssignmentRule
						,productionTimeSource
					)
				WHEN MATCHED THEN
					UPDATE
						SET
							 ppProductionTimeMinutes = productionTimeMinutes
							,ppProductionTimeAssignmentRule = productionTimeAssignmentRule
							,ppProductionTimeSource = productionTimeSource;

				-- debug
				--PRINT 'debug'

				------------------------------------------------------------------------------------------------------------------------------------------------------------
				-- Csomópontok: DE
				------------------------------------------------------------------------------------------------------------------------------------------------------------
				-- gyártási idő kiszámolása a szkennelt alkatrészekhez rendelt idők összegzésével
				DECLARE @productionTimeMinutesSum FLOAT =
				(
					SELECT
						SUM(ppProductionTimeMinutes)
					FROM
						@indexedProductionActivity
						INNER JOIN WitturToolsProd.dbo.ProductionProduct ON ppProductionActivity = productionActivity
					WHERE
						scannedProductCount != 0
						AND ppPTSProductTracking IS NOT NULL
					GROUP BY
						productionMeasurePoint	
				)

				-- SemiFinish idő összegzése
				DECLARE @semiFinishTimeMinutes FLOAT =
				(
					SELECT
						SUM(pdLengthMinutes)
					FROM
						@indexedProductionActivity
						INNER JOIN WitturToolsProd.dbo.ProductionDowntime ON pdProductionActivity = productionActivity
					WHERE
						pdPTSDowntime = 41 -- Semi-Finish
					GROUP BY
						productionMeasurePoint
				)

				-- Címke nélküli gyártási idő összegzése
				DECLARE @manufacturingWithoutLabelTimeMinutes FLOAT =
				(
					SELECT
						SUM(pdLengthMinutes)
					FROM
						@indexedProductionActivity
						INNER JOIN WitturToolsProd.dbo.ProductionDowntime ON pdProductionActivity = productionActivity
					WHERE
						pdPTSDowntime = 63 -- Címke nélküli gyártás
					GROUP BY
						productionMeasurePoint
				)

				DECLARE @allProductionTimeMinutes FLOAT = ISNULL(@productionTimeMinutesSum, 0) + ISNULL(@semiFinishTimeMinutes, 0) + ISNULL(@manufacturingWithoutLabelTimeMinutes, 0)

				-- debug
				--SELECT @allProductionTimeMinutes

				INSERT INTO @productionWaterfallTemp
				(
					 productionMeasurePoint
					,waterfallEntry
					,timeMinutes
				)
				SELECT
					 @ProductionMeasurePoint_pmpId
					,60 -- Nem lefedett idő
					,-SUM(@sumOfTimeMinutes - @allProductionTimeMinutes)

				------------------------------------------------------------------------------------------------------------------------------------------------------------
				-- Csomópont: D -> Működési idő
				------------------------------------------------------------------------------------------------------------------------------------------------------------
				-- részösszeg számítás
				SELECT
					@sumOfTimeMinutes = SUM(timeMinutes)
				FROM
					@productionWaterfallTemp
					INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = waterfallEntry
					INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
				WHERE
					wepPositionLetter IN('D', 'DE')

				INSERT INTO @productionWaterfallTemp
				(
					 productionMeasurePoint
					,waterfallEntry
					,timeMinutes
				)
				SELECT
					 @ProductionMeasurePoint_pmpId
					,61 -- Működési idő
					,@sumOfTimeMinutes

				-- ha nem nulla a Működési idő csak akkor van értelme tovább menni
				IF @sumOfTimeMinutes != 0
				BEGIN

					------------------------------------------------------------------------------------------------------------------------------------------------------------
					-- Csomópont: EF -> Selejt
					------------------------------------------------------------------------------------------------------------------------------------------------------------
					DECLARE @scrapTimeMinutes FLOAT =
					(
						SELECT
							SUM(ppProductionTimeMinutes)
						FROM
							WitturToolsProd.dbo.ProductionMeasurePoint
							INNER JOIN WitturToolsProd.dbo.ProductionActivity ON paProductionMeasurePoint = pmpId
							INNER JOIN WitturToolsProd.dbo.ProductionProduct ON ppProductionActivity = paId
						WHERE
							pmpId = @ProductionMeasurePoint_pmpId
							AND ppProductionScrap IS NOT NULL
					)

					IF ISNULL(@scrapTimeMinutes, 0) != 0
					BEGIN

						INSERT INTO @productionWaterfallTemp
						(
							 productionMeasurePoint
							,waterfallEntry
							,timeMinutes
						)
						SELECT
							 @ProductionMeasurePoint_pmpId
							,62 -- Selejt
							,-@scrapTimeMinutes

					END

					------------------------------------------------------------------------------------------------------------------------------------------------------------
					-- Csomópont: EF -> Újragyártás
					------------------------------------------------------------------------------------------------------------------------------------------------------------
					DECLARE @reproductionTimeMinutes FLOAT =
					(
						SELECT
							SUM(ppProductionTimeMinutes)
						FROM
						(
							SELECT
								 IIF(prdHead IS NOT NULL, 1, 0) isReproduction
								,ppProductionTimeMinutes
							FROM
								WitturToolsProd.dbo.ProductionMeasurePoint
								INNER JOIN WitturToolsProd.dbo.ProductionActivity ON paProductionMeasurePoint = pmpId
								INNER JOIN WitturToolsProd.dbo.ProductionProduct ON ppProductionActivity = paId
								INNER JOIN PTS.dbo.ProductTracking WITH (READPAST) ON ptrid = ppPTSProductTracking
								INNER JOIN PTS.dbo.Product WITH (READPAST) ON prdid = ptrProduct
							WHERE
								pmpId = @ProductionMeasurePoint_pmpId
								AND ppPTSProductTracking IS NOT NULL
						) i
						WHERE
							i.isReproduction = 1
					)

					--DECLARE @reproductionTimeMinutes FLOAT =
					--(
					--	SELECT
					--		SUM(ppProductionTimeMinutes)
					--	FROM
					--	(
					--		SELECT
					--			 (
					--				CASE
					--					WHEN ppPTSProductTracking IS NOT NULL THEN
					--					(
					--						SELECT
					--							IIF(prdHead IS NOT NULL, 1, 0)
					--						FROM
					--							PTS.dbo.ProductTracking
					--							INNER JOIN PTS.dbo.Product ON prdid = ptrProduct
					--						WHERE
					--							ptrid = ppPTSProductTracking
					--					)
					--					WHEN ppProductionScrap IS NOT NULL THEN
					--					(
					--						SELECT
					--							IIF(prdHead IS NOT NULL, 1, 0)
					--						FROM
					--							WitturToolsProd.dbo.ProductionScrap
					--							INNER JOIN PTS.dbo.BarCode ON barid = psPTSBarCode
					--							INNER JOIN PTS.dbo.Product ON prdId = barProduct
					--						WHERE
					--							psId = ppProductionScrap
					--					)
					--				END
					--			 ) isReproduction
					--			,ppProductionTimeMinutes
					--		FROM
					--			WitturToolsProd.dbo.ProductionMeasurePoint
					--			INNER JOIN WitturToolsProd.dbo.ProductionActivity ON paProductionMeasurePoint = pmpId
					--			INNER JOIN WitturToolsProd.dbo.ProductionProduct ON ppProductionActivity = paId
					--		WHERE
					--			pmpId = @ProductionMeasurePoint_pmpId
					--	) i
					--	WHERE
					--		i.isReproduction = 1
					--)

					IF ISNULL(@reproductionTimeMinutes, 0) != 0
					BEGIN

						INSERT INTO @productionWaterfallTemp
						(
							 productionMeasurePoint
							,waterfallEntry
							,timeMinutes
						)
						SELECT
							 @ProductionMeasurePoint_pmpId
							,63 -- Újragyártás
							,-@reproductionTimeMinutes

					END

					------------------------------------------------------------------------------------------------------------------------------------------------------------
					-- Csomópont: D -> Értékteremtési idő
					------------------------------------------------------------------------------------------------------------------------------------------------------------
					-- részösszeg számítás
					SELECT
						@sumOfTimeMinutes = SUM(timeMinutes)
					FROM
						@productionWaterfallTemp
						INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = waterfallEntry
						INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
					WHERE
						wepPositionLetter IN('E', 'EF')

					INSERT INTO @productionWaterfallTemp
					(
						 productionMeasurePoint
						,waterfallEntry
						,timeMinutes
					)
					SELECT
						 @ProductionMeasurePoint_pmpId
						,64 -- Értékteremtési idő
						,@sumOfTimeMinutes

				END
			END
		END
	END
	
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- Műszak offset kalkuláció
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- pozíció jelölő frissítése
	UPDATE
		t
	SET
		t.positionLetter = s.wepPositionLetter
	FROM
		@productionWaterfallTemp t
		INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = waterfallEntry
		INNER JOIN WaterfallEntryPosition s ON wepId = weWaterfallEntryPosition;

	-- sorszám létrehozása
	WITH rownumberedProductionWaterfallTemp AS 
	(
		SELECT 
			*,
			ROW_NUMBER() OVER (
				ORDER BY 
					CASE positionLetter
						WHEN 'A'  THEN 0
						WHEN 'AB' THEN 1
						WHEN 'B'  THEN 2
						WHEN 'BC' THEN 3
						WHEN 'C'  THEN 4
						WHEN 'CD' THEN 5
						WHEN 'D'  THEN 6
						WHEN 'DE' THEN 7
						WHEN 'E'  THEN 8
						WHEN 'EF' THEN 9
						WHEN 'F'  THEN 10
					END,
					CASE
						WHEN positionLetter IN ('AB', 'BC', 'CD', 'DE', 'EF') THEN timeMinutes
					END ASC
			) AS rn
		FROM 
			@productionWaterfallTemp
	)

	-- sorszám frissítése
	UPDATE
		t
	SET
		t.rowNumber = s.rn
	FROM
		@productionWaterfallTemp t
		INNER JOIN rownumberedProductionWaterfallTemp s ON t.waterfallEntry = s.waterfallEntry
														   AND t.timeMinutes = s.timeMinutes;
			
	-- ciklus változók deklaráció és inicializálás
	DECLARE @currentIndexINT INT =
	(
		SELECT
			MIN(rowNumber)
		FROM
			@productionWaterfallTemp
	)

	DECLARE @currentOffsetFLOAT FLOAT = 0

	WHILE @currentIndexINT IS NOT NULL
	BEGIN

		-- érték meghatározása
		SET @currentOffsetFLOAT =
		(
			CASE
				-- a fő csomópontok offsettje mindig nulla
				WHEN 
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) IN ('A', 'B', 'C', 'D', 'E', 'F') THEN 0
				-- aktuális AB, előző A
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'AB'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'A'
				THEN
				(
					SELECT 
						timeMinutes
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						ABS(timeMinutes)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
				-- aktuális BC, előző B
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'BC'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'B'
				THEN
				(
					SELECT 
						timeMinutes
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						ABS(timeMinutes)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
				-- aktuális BC, előző BC
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'BC'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'BC'
				THEN
				(
					SELECT 
						offset
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						ABS(timeMinutes)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
				-- aktuális CD, előző C
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'CD'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'C'
				THEN
				(
					SELECT 
						timeMinutes
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						ABS(timeMinutes)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
				-- aktuális CD, előző CD
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'CD'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'CD'
				THEN
				(
					SELECT 
						offset
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						ABS(timeMinutes)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
				-- aktuális DE, előző D
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'DE'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'D'
				THEN
				(
					SELECT 
						timeMinutes
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						IIF(timeMinutes < 0, ABS(timeMinutes), 0)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
				-- aktuális DE, előző DE
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'DE'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'DE'
				THEN
				(
					SELECT 
						offset
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						ABS(timeMinutes)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
				--------------------------------------
				-- aktuális DE, előző D
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'EF'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'E'
				THEN
				(
					SELECT 
						timeMinutes
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						ABS(timeMinutes)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
				-- aktuális DE, előző DE
				WHEN
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				) = 'EF'
				AND
				(
					SELECT 
						positionLetter
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				) = 'EF'
				THEN
				(
					SELECT 
						offset
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = (@currentIndexINT - 1)
				)
				-
				(
					SELECT 
						ABS(timeMinutes)
					FROM
						@productionWaterfallTemp
					WHERE
						rowNumber = @currentIndexINT
				)
			END
		)

		-- offset frissítés
		UPDATE
			t
		SET
			t.offset = @currentOffsetFLOAT
		FROM
			@productionWaterfallTemp t
		WHERE
			t.rowNumber = @currentIndexINT

		-- ciklus léptetés
		SET @currentIndexINT =
		(
			SELECT
				MIN(rowNumber)
			FROM
				@productionWaterfallTemp
			WHERE
				rowNumber > @currentIndexINT
		)

	END

	-- debug
	--SELECT * FROM @productionWaterfallTemp ORDER BY rowNumber
	
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- adatmentés / frissítés -> WitturToolsProd.dbo.ProductionWaterfall
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- debug
	--SELECT * FROM @productionWaterfallTemp
	
	MERGE INTO 
		WitturToolsProd.dbo.ProductionWaterfall t
	USING 
		@productionWaterfallTemp s
	ON 
		t.pwProductionMeasurePoint = s.productionMeasurePoint
		AND t.pwWaterfallEntry = s.waterfallEntry
	WHEN NOT MATCHED BY TARGET THEN
		INSERT 
		(
			 pwProductionMeasurePoint
			,pwWaterfallEntry
			,pwTimeMinutes
			,pwOffset
		)
		VALUES 
		(
			 s.productionMeasurePoint
			,s.waterfallEntry
			,s.timeMinutes
			,s.offset
		)
	WHEN MATCHED THEN
		UPDATE SET
			 t.pwTimeMinutes = s.timeMinutes
			,t.pwOffset = s.offset;

	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- adatmentés / frissítés -> WitturToolsProd.dbo.ProductionKeyPerformanceIndicatorValue
	------------------------------------------------------------------------------------------------------------------------------------------------------------
	-- összesítés
	DECLARE @productionKeyPerformanceIndicatorValue TABLE
	(
		 productionMeasurePoint INT
		,kpiValueDescription INT
		,[value] FLOAT
	)
	
	-- OEE
	DECLARE @availabilityIndicator FLOAT =
	(
		(
			SELECT
				pwTimeMinutes
			FROM
				WitturToolsProd.dbo.ProductionWaterfall
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = pwWaterfallEntry
				INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
			WHERE
				pwProductionMeasurePoint = @ProductionMeasurePoint_pmpId
				AND wepPositionLetter = 'D'
		)
		/
		NULLIF((
			SELECT
				pwTimeMinutes
			FROM
				WitturToolsProd.dbo.ProductionWaterfall
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = pwWaterfallEntry
				INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
			WHERE
				pwProductionMeasurePoint = @ProductionMeasurePoint_pmpId
				AND wepPositionLetter = 'C'
		), 0)
	)

	INSERT INTO @productionKeyPerformanceIndicatorValue
	(
		 productionMeasurePoint
		,kpiValueDescription
		,[value]
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,1 -- Rendelkezésre állás
		,@availabilityIndicator
	WHERE
		@availabilityIndicator IS NOT NULL

	DECLARE @performanceIndicator FLOAT =
	(
		(
			SELECT
				pwTimeMinutes
			FROM
				WitturToolsProd.dbo.ProductionWaterfall
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = pwWaterfallEntry
				INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
			WHERE
				pwProductionMeasurePoint = @ProductionMeasurePoint_pmpId
				AND wepPositionLetter = 'E'
		)
		/
		NULLIF((
			SELECT
				pwTimeMinutes
			FROM
				WitturToolsProd.dbo.ProductionWaterfall
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = pwWaterfallEntry
				INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
			WHERE
				pwProductionMeasurePoint = @ProductionMeasurePoint_pmpId
				AND wepPositionLetter = 'D'
		), 0)
	)

	INSERT INTO @productionKeyPerformanceIndicatorValue
	(
		 productionMeasurePoint
		,kpiValueDescription
		,[value]
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,2 -- Teljesítmény
		,@performanceIndicator
	WHERE
		@performanceIndicator IS NOT NULL

	DECLARE @qualityIndicator FLOAT =
	(
		(
			SELECT
				pwTimeMinutes
			FROM
				WitturToolsProd.dbo.ProductionWaterfall
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = pwWaterfallEntry
				INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
			WHERE
				pwProductionMeasurePoint = @ProductionMeasurePoint_pmpId
				AND wepPositionLetter = 'F'
		)
		/
		NULLIF((
			SELECT
				pwTimeMinutes
			FROM
				WitturToolsProd.dbo.ProductionWaterfall
				INNER JOIN WitturToolsProd.dbo.WaterfallEntry ON weId = pwWaterfallEntry
				INNER JOIN WitturToolsProd.dbo.WaterfallEntryPosition ON wepId = weWaterfallEntryPosition
			WHERE
				pwProductionMeasurePoint = @ProductionMeasurePoint_pmpId
				AND wepPositionLetter = 'E'
		), 0)
	)
	
	INSERT INTO @productionKeyPerformanceIndicatorValue
	(
		 productionMeasurePoint
		,kpiValueDescription
		,[value]
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,3 -- Minőség
		,@qualityIndicator
	WHERE
		@qualityIndicator IS NOT NULL

	INSERT INTO @productionKeyPerformanceIndicatorValue
	(
		 productionMeasurePoint
		,kpiValueDescription
		,[value]
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,4 -- Teljes eszközhatékonyság
		,@availabilityIndicator * @performanceIndicator * @qualityIndicator
	WHERE
		@availabilityIndicator IS NOT NULL
		AND @performanceIndicator IS NOT NULL
		AND @qualityIndicator IS NOT NULL

	INSERT INTO @productionKeyPerformanceIndicatorValue
	(
		 productionMeasurePoint
		,kpiValueDescription
		,[value]
	)
	SELECT
		 @ProductionMeasurePoint_pmpId
		,97 -- Adathiba
		,IIF
		(
			(@availabilityIndicator IS NULL OR (@availabilityIndicator IS NOT NULL AND @availabilityIndicator NOT BETWEEN 0 AND 1))
			OR (@performanceIndicator IS NULL OR (@performanceIndicator IS NOT NULL AND @performanceIndicator NOT BETWEEN 0 AND 1))
			OR (@qualityIndicator IS NULL OR (@qualityIndicator IS NOT NULL AND @qualityIndicator NOT BETWEEN 0 AND 1))
		,1 ,0 )

	INSERT INTO @productionKeyPerformanceIndicatorValue
	(
		productionMeasurePoint
		,kpiValueDescription
		,[value]
	)
	SELECT
		@ProductionMeasurePoint_pmpId
		,5 -- Gyártott darab
		,COUNT(*)
	FROM
		WitturToolsProd.dbo.ProductionActivity
		INNER JOIN WitturToolsProd.dbo.ProductionProduct ON ppProductionActivity = paId
	WHERE
		paProductionMeasurePoint = @ProductionMeasurePoint_pmpId

	INSERT INTO @productionKeyPerformanceIndicatorValue
	(
		productionMeasurePoint
		,kpiValueDescription
		,[value]
	)
	SELECT
		@ProductionMeasurePoint_pmpId
		,96 -- Újragyártott darab
		,COUNT(*)
	FROM
		WitturToolsProd.dbo.ProductionActivity
		INNER JOIN WitturToolsProd.dbo.ProductionProduct ON ppProductionActivity = paId
		INNER JOIN PTS.dbo.ProductTracking WITH (READPAST) ON ptrid = ppPTSProductTracking
		INNER JOIN PTS.dbo.Product WITH (READPAST) ON prdid = ptrProduct
	WHERE
		paProductionMeasurePoint = @ProductionMeasurePoint_pmpId
		AND ppPTSProductTracking IS NOT NULL
		AND prdHead IS NOT NULL

	-- Állásidő összesítők készítése a műszakhoz -> KeyPerformanceIndicatorValueDescription, ahol kpivdPTSDowntime nem null
	INSERT INTO @productionKeyPerformanceIndicatorValue
	(
		productionMeasurePoint
		,kpiValueDescription
		,[value]
	)
	SELECT
		@ProductionMeasurePoint_pmpId
		,kpivdId
		,SUM(pdLengthMinutes)
	FROM
		WitturToolsProd.dbo.ProductionActivity
		INNER JOIN WitturToolsProd.dbo.ProductionDowntime ON pdProductionActivity = paId
		INNER JOIN WitturToolsProd.dbo.KeyPerformanceIndicatorValueDescription ON kpivdPTSDowntime = pdPTSDowntime
	WHERE
		paProductionMeasurePoint = @ProductionMeasurePoint_pmpId
	GROUP BY
		kpivdId

	-- adatok írása és frissítése
	MERGE INTO 
		WitturToolsProd.dbo.ProductionKeyPerformanceIndicatorValue t
	USING @productionKeyPerformanceIndicatorValue s
	ON 
		t.pkpivProductionMeasurePoint = s.productionMeasurePoint
		AND t.pkpivKPIValueDescription = s.kpiValueDescription
	WHEN NOT MATCHED BY TARGET THEN
		INSERT 
		(
			 pkpivProductionMeasurePoint
			,pkpivKPIValueDescription
			,pkpivValue
		)
		VALUES 
		(
			 s.productionMeasurePoint
			,s.kpiValueDescription
			,s.[value]
		)
	WHEN MATCHED AND t.pkpivValue != s.[value] THEN
		UPDATE SET
			t.pkpivValue = s.[value];

END
