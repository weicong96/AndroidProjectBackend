config = require("./config")
fs = require("fs")
jsdom = require("jsdom").jsdom
unzip = require("unzip")
mongodb = require('mongodb').MongoClient
request = require("request")
Firebase = require("firebase")
parseXlsx = require("excel")
class App
	Models : {}
	constructor : ->
		@config = config
		@mongo = mongodb.connect @config.mongodb.url,(err, db)=>
			if !err
				if db
					@mongo = db 
					@initModels()
					
					setInterval ()=>
						@insertData()
					, 2 * 60 * 60 * 1000
					@insertData()
	insertData : ()=>
		latestData = []
		firebaseRef = new Firebase("http://amber-heat-3566.firebaseio.com/weicong")
		request { url : "http://weicong.chickenkiller.com/data?parkid=55880521ecdaf52b36b15e6a", port : 80 , method : "GET"}, (error, response)=>
			for park in JSON.parse(response.body)
				for datasource in park["data"]
					data = datasource[datasource.length - 1]	
					latestData.push { name : data["id"]["name"] , data : data["data"]}
			randomizedPoints = []
			parseXlsx "cord_excel.xlsx", (err,data)=>
				data = data.splice(0, data.length-1)
				if !err and data 
					insertEntry =
							dateInsertedMilliseconds : new Date().getTime()
							dateInsertedString : new Date().toJSON()
					for latest in latestData
						if insertEntry["data"] is undefined
							insertEntry["data"] = []
						entriesArray = []

						for dataRow in data
							lat = parseFloat(dataRow[0])
							lng = parseFloat(dataRow[1])

							random = Math.round(Math.floor(Math.random() * (parseFloat(latest["data"]) * 1.20)) + (parseFloat(latest["data"]) * 0.8))
							
							entriesArray.push {data : random, lat : lat, lng: lng}
						insertEntry["data"].push {type : latest["name"], entries : entriesArray}
						#randomizedPoints.push {dateInsertedString : new Date().toJSON(), dateInsertedMilliseconds : new Date().getTime()}
					firebaseRef.push insertEntry
				#firebaseRef.push {parkName : park["name"], data : randomizedPoints, dateInsertedString : new Date().toJSON(), dateInsertedMilliseconds : new Date().getTime()}
	initModels : () =>
        @Models.HotspotHistory = @mongo.collection("hs")
new App()
module.exports = App
