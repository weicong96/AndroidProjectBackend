request = require("request")
unzip = require("unzip")
config = require("./config")
CronJob = require("cron").CronJob
geojson = require("togeojson")
fs = require("fs")
jsdom = require("jsdom").jsdom
unzip = require("unzip")
mongodb = require('mongodb').MongoClient
ObjectId = require('mongodb').ObjectID;
Q = require("q")
class App
	Models : {}
	constructor : ->
		@config = config
		@mongo = mongodb.connect @config.mongodb.url,(err, db)=>
			if !err
				if db
					@mongo = db 
					@initModels()
					job = new CronJob {
						cronTime : "00 00 12 * * *",
						onTick : ()=>
							for url in @config.urls 
								newUrl = ""
								newUrl = url.split("ThemeName=")[1].split "&MetaDataID"

								@getResponse(url, newUrl)
						start : true,
						timeZone : "Asia/Singapore"
					}
					job.start()
					types = []
					for url in @config.urls 
						newUrl = ""
						newUrl = url.split("ThemeName=")[1].split "&MetaDataID"
						types.push newUrl[0]
						@getResponse(url, newUrl)

					
					#@getResponseOLDRewrite(types)
	findHotspotOnDay : (day , type)=>
		defer = Q.defer();
		twoWeeksAgo = new Date(day.getTime() - 14 * 24 * 60 * 60 * 1000)
		twoWeeksAgo.setHours 0, 0, 0, 0

		day.setHours 23, 59, 0, 0

		@Models.HotspotHistory.find({appearedOn : {$lt : day , $gt : twoWeeksAgo}}).toArray (err,doc)=>
			if !err and doc

				defer.resolve {items : doc, type : type}
			else
				console.log "error"
				defer.reject []
		return defer.promise;

	getResponseOLDRewrite : (types)=>
		#Read from new file
		index = 0
		# Step 1) Load coordinates from file
		# Step 2) Check coordinate for existence today BUT NOT past two weeks
		# Step 2a) If past two weeks does not exists, insert
		# Step 2b) If past two weeks exists, do not do anything
		# Step 3) Check coordinate for no today existence AND existence yesterday (Can be done seperately I think)

		#Problem : There may be coordinates that are duplicated across multiple files, in which case i need to insert and wait for callback before finding again
		#This is a major problem, because there is no way for this to wait on previous items 
		allTheItems = []
		filesToLoad = ["_2015-07-27", "_2015-07-28","_2015-07-29", "_2015-07-30" , "_2015-07-31","_2015-08-01","_2015-08-02","_2015-08-03" ,"_2015-08-04" ,"_2015-08-05" ,"_2015-08-06" ,"_2015-08-07","_2015-08-08", "_2015-08-09"]
		for load in filesToLoad
			date = new Date(load.replace("_",""))
			for type in types
				date = new Date(load.replace "_", "")
				fileName = type+load
				kml = geojson.kml(jsdom fs.readFileSync("../app-server/kml/history/"+fileName+".kml"))
				
				getFeature = (kml, date, fileName)=>
					featureCoordinates = []
					for feature in kml["features"]
						for coordinates in feature["geometry"]["coordinates"]
							for coordinate in [coordinates[0]]

								featureCoordinates.push coordinate
								#Problem : by the time found got back, already loop finish
								getCoordinateInsertToday = (coordinate, date, fileName)=>
									@Models.HotspotHistory.find({lat : coordinate[1], lng : coordinate[0]}).toArray (err,allData)=>
										if !err and allData		
											found = false
											for item in allTheItems
												if item["lat"] is coordinate[1] and item["lng"] is coordinate[0]
													found = true
													#console.log "Found"
													break;
											if allData.length is 0 and found is false 
												hotspot = 
													lat : coordinate[1]
													lng : coordinate[0]
													appearedOn : date
													type : type
													description : feature["properties"]["description"]
												allTheItems.push hotspot
												@Models.HotspotHistory.insert hotspot, (err, doc)=>
										else 
											console.log err
								getCoordinateInsertToday coordinate, date, fileName
				getFeature kml, date,fileName
	getResponse : (url, newUrl)=>
		console.log "Running #{new Date()}"
		allTheItems = []
		request({ url : url, port : 80 , method : "GET"}).on("response" , (response)=>
			date = new Date()
			twoWeeksAgo = new Date(new Date().getTime() - 1000 * 60 * 60 * 24 * 14)
			oldFileName = newUrl[0]+"_"+date.toJSON().slice(0,10)
			#Move previous file to history folder
			fileName = newUrl[0]
			source = fs.createReadStream("../app-server/kml/"+newUrl[0]+".kml")
			dest = fs.createWriteStream("../app-server/kml/history/"+oldFileName+".kml")

			source.pipe dest, {end : false}
			source.on "end", ()=>
				count = 0
				#Unzip to new file
				reader = fs.createReadStream(""+newUrl[0]+".zip")
				reader.pipe(unzip.Extract({path: "../app-server/kml"}))
				reader.on "end" , ()=>
					kml = geojson.kml(jsdom fs.readFileSync("../app-server/kml/"+fileName+".kml"))
					date = new Date()
					getFeature = (kml, date, fileName)=>
						featureCoordinates = []
						for feature in kml["features"]
							for coordinates in feature["geometry"]["coordinates"]
								for coordinate in [coordinates[0]]

									featureCoordinates.push coordinate
									#Problem : by the time found got back, already loop finish
									getCoordinateInsertToday = (coordinate, date, fileName)=>
										@Models.HotspotHistory.find({lat : coordinate[1], lng : coordinate[0]}).toArray (err,allData)=>
											if !err and allData		
												found = false
												for item in allTheItems
													if item["lat"] is coordinate[1] and item["lng"] is coordinate[0]
														found = true
														#console.log "Found"
														break;
												if allData.length is 0 and found is false 
													hotspot = 
														lat : coordinate[1]
														lng : coordinate[0]
														appearedOn : date
														type : type
														description : feature["properties"]["description"]
													allTheItems.push hotspot
													@Models.HotspotHistory.insert hotspot, (err, doc)=>
														if !err and doc 
															console.log "Inserted"
											else 
												console.log err
									getCoordinateInsertToday coordinate, date, fileName
					getFeature kml, date,fileName

		).pipe(fs.createWriteStream(""+newUrl[0]+".zip"))
	initModels : () =>
        @Models.HotspotHistory = @mongo.collection("hs")
new App()
module.exports = App
