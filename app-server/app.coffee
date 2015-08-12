http = require('http')
config = require("./config")
mongodb = require('mongodb').MongoClient
express = require('express')
bodyParser = require("body-parser")
ObjectId = require('mongodb').ObjectID;
request = require("request")
fs = require("fs")
xml2js = require("xml2js")

Formula = require("./routes/formula")
Park = require("./routes/park")
Dataset = require("./routes/dataset")
Data = require("./routes/data")
Hotspot = require("./routes/hotspots")
WeatherForecast = require("./routes/weatherforecast")
class App
	Models : {}
	constructor : ->
		@config = config
		@router = express()
		@router.use "/kml" , express.static(__dirname+"/kml")
		@router.use express.json()
		@router.use express.urlencoded()

		@router.use (req, res, next)=>
			res.setHeader "Access-Control-Allow-Origin", "*"
			res.setHeader "Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, OPTIONS, DELETE"
			res.setHeader "Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept"
			res.setHeader "Access-Control-Allow-Credentials", true
			next()
		@server = @router.listen 80, ()=>
			host = @server.address().address;
			port = @server.address().port;

			console.log "Server running at http://#{host}:#{port}/"
		@Q = require("q")
		@mongo = mongodb.connect @config.mongodb.url,(err, db)=>
			if !err
				if db
					@mongo = db
					console.log "Mongodb started"
					@initModels()
					@initRoutes()

	objectID : (id) =>
		return new ObjectId(id)
	log : (text) =>
		console.log "[#{@config.appname}] @ "+new Date() + " : "+text
	initRoutes : () =>
		@formulaRoute = new Formula @
		@parkRoute = new Park @
		@dataRoute = new Data @
		@datasetRoute = new Dataset @
		@forecastRoute = new WeatherForecast @
		@hotspotRoute = new Hotspot @
	initModels : () =>
		@Models.Formula = @mongo.collection("formula")
		@Models.Data = @mongo.collection("data")
		@Models.Park = @mongo.collection("park")
		@Models.Dataset = @mongo.collection("dataset")
		@Models.HotspotHistory = @mongo.collection("hs")
		@Models.Alerts = @mongo.collection("alerts")
	sendError: (req,res, errorCode, message)=>
		res.status errorCode
		return res.send {"error" : message}
	sendAdminError: (req,res, message)=>
		res.status 500
		return res.send {"error": message}
	sendContent: (req,res, content)=>
		res.status 200
		return res.json content
new App()
module.exports = App
