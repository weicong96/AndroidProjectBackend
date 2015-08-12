http = require('http')
mongodb = require('mongodb').MongoClient
express = require('express')
bodyParser = require("body-parser")
ObjectId = require('mongodb').ObjectID

class App
	Models : {}
	constructor : ->
		@router = express()
		@router.use express.json()
		@router.use express.urlencoded()
		@router.use express.bodyParser {uploadDir:'./uploads'} 
		@server = @router.listen 3001, ()=>
			host = @server.address().address;
			port = @server.address().port;

			console.log "Server running at http://#{host}:#{port}/"
		@mongo = mongodb.connect "mongodb://localhost:27017/ccapp",(err, db)=>
			if !err
				if db
					@mongo = db
					@initRoutes()
					@initModels()
					console.log "Mongodb started"
	initModels : () =>
		@Models.rotation = @mongo.collection("rotation")
	log : (text) =>
		console.log "[#{@config.appname}] @ "+new Date() + " : "+text
	sendError: (req,res, errorCode, message)=>
		res.status errorCode
		return res.send {"error" : message}
	sendAdminError: (req,res, message)=>
		res.status 500
		return res.send {"error": message}
	sendContent: (req,res, content)=>
		res.status 200
		return res.json content
	initRoutes: ()=>
		@router.get "/rotation", (req, res)=>
			@Models.rotation.find({}).toArray (err,data)=>
				if !err
					if data
						results = []
						for result in data
							a = new Date(parseInt(result.time));
							months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
							year = a.getFullYear();
							month = months[a.getMonth()];
							date = a.getDate();
							hour = a.getHours();
							min = a.getMinutes();
							sec = a.getSeconds();
							time = date + ',' + month + ' ' + year + ' ' + hour + ':' + min + ':' + sec ;
							result.time = time

							results.push result
						return @sendContent req, res, results
					else
						return @sendError req, res, 404, "No data"
				else
					return @sendAdminError req, res, err
		@router.post "/rotation", (req,res)=>
			rotation = 
				last : req.body.last
				_new : req.body._new
				change : req.body.change
				time : req.body.time
			@Models.rotation.insert rotation, (err, data)=>
				if !err
					if data
						console.log rotation
						return @sendContent req, res, data
					else
						return @sendError req, res, 404, "Could not insert "
				else
					return @sendAdminError req, res, err
		@router.post "/rotation/photo/{id}", (req, res)=>
			@Models.rotation.update {_id : new ObjectId(req.params.id)}, {$set : {photo : req.files.photo.name}}, (err, data)=>
				if !err
					if data
						return @sendContent req, res, ""
					else
						return @sendError req, res, 404, "Could not insert"
				else
					return @sendAdminError req, res, err  
new App()
module.exports = App