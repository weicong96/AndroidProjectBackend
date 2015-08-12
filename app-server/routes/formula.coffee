request = require("request")
Firebase = require("firebase")
class Datasource
	
	constructor : (@App)->
		routeName= "formula"
		@App.router.get "/#{routeName}/using", @getFormulaUsing
		@App.router.get "/#{routeName}/response", @getResponseForClient
		@App.router.get "/#{routeName}", @getFormulas
		@App.router.post "/#{routeName}", @postFormula
		@App.router.put "/#{routeName}/:id", @putFormula	
		@App.router.get "/#{routeName}/:id", @getFormula
		@App.router.get "/#{routeName}/calculate", @calculate
		@App.router.get "/triggerNoti", @triggerNotifications

		@rest = require("restler")
	triggerNotifications : (req, res)=>
		
		firebaseRef = new Firebase("http://amber-heat-3566.firebaseio.com/yuhan2/userdata")
		sent = false
		firebaseRef.on "child_added", (snapshot, prev)=>
			value = snapshot.val()
			messages = {}
			device_id = ""
			if Boolean(value["ang_mo_kio_park"]) is true
				messages = {message : "AMK park has entered Red risk status for Dengue alert!"}
				device_id = value["device_id"]

			dataToSend = 
				registration_ids : [device_id]
				data: messages
			
			request { url : "https://pushy.me/push?api_key=ef633ad09f1ddb6107205bedcee1e8528b154f90993f235e83033371258af4e5", method : "POST", headers: { "content-type" : "application/json"}, json : true, body: dataToSend }, (err, response)=>
				console.log response
				if sent is false
					sent = true
					@App.Models.Park.update {_id : @App.objectID("55880525ecdaf52b36b15e6b")} , {$set : {risk : "red"}}, (err,doc)=>
						if !err and doc
							return @App.sendContent req, res, {message : "Sent notification successfully"}
				
	calculate : (req, res)=>
		windspeed = req.query.windspeed
		surfaceArea = 10 * 25
		xs = req.query.temperature / 1000
		x = 0.0098
		v = 0.5

		result = (25 + 19 * windspeed)(surfaceArea)(xs - x)/3600

		console.log result
	getFormulaUsing : (req ,res )=>
		id = @App.objectID("5586582f20b645a832e4adc4")
		@App.Models.Formula.findOne {"using" : "true", _id : id},(err, data)=>
			if !err
				if data
					return @App.sendContent req, res, data
			else
				return @App.sendAdminError req, res, err
	getResponseForClient : (req, res) =>
		if req.query.url
			req.query.url = decodeURI(req.query.url)
			@rest.get(req.query.url).on "complete", (response)=>
				mainData = {}

				mainData.text = JSON.stringify response

				#Got to work out recursive keys
				#mainData.avaliableKeys = Object.keys(response);
				allKeys = mainData.avaliableKeys
				getNestedKeys = (response, _data)=>
					#for key in data
					#	data = response[key]
					#	if data instanceof Array
					#		console.log "data is array"
					#		for item in data
					#			return getNestedKeys(response,Object.keys(item))
					#	else if data instanceof Object
					#		console.log "data is object"
					#		return getNestedKeys(response,Object.keys(data))
						#If it's not either of these, means it's a node
					#	else
					#		mainData.avaliableKeys.push data
					#		return 1;
					return Object.keys(response)
				data = getNestedKeys response,response
				return @App.sendContent req, res,data
			
		else
			return @App.sendContent req, res, []
	putFormula : (req, res) =>
		console.log @App.objectID(req.params.id)
		delete req.body._id 
		@App.Models.Formula.update {_id : new @App.objectID(req.params.id)} , {$set :req.body}, (err,data)=>
			if !err
				if data
					return @App.sendContent req, res,  data
			else
				return @App.sendAdminError req, res, err
	postFormula : (req, res) =>
		#	Instead of calculating evaporation rate, formula tracks the following:
		#			Humidity OR/AND Temperature in area
		#			Amount of rainfall OR rain status(Thunderstorm, etc.)
		#			
		#
		#	User defines patterns to look out for, etc. : 
		#		n consective number of rainy days + m number of humid days below certain temperature
		#		
		#	When saved, system recalculates and reevaluates all previous data that has been handled before
		#	name
		#	inuse
		#   status 
		#			-statusValue
		#			-patterns : 
				#			-frequency
				#           -occurences
				#		    -value
				#		    -compare factor
				#			-datasetID
		if !req.body.name
			return @App.sendError req, res, 404, "Please give a name!"
		if !req.body.statuses
			return @App.sendError req, res, 404, "Please define status"
		if !req.body.using
			return @App.sendError req, res, 404, "Please define using"
		for status in req.body.statuses
			if !status.statusValue
				return @App.sendError req, res, 404, "Please define statusValue"
			for patterns in status.patterns
				if !patterns.frequency 
					return @App.sendError req, res, 404, "Please define frequency"
				if !patterns.occurences
					return @App.sendError req, res, 404, "Please define occurences"
				if !patterns.value
					return @App.sendError req, res, 404, "Please define value"
				if !patterns.compare
					return @App.sendError req, res, 404, "Please define compare"
				if !patterns.datasetID
					return @App.sendError req, res, 404, "Please define datasetID"

		formula =
			name :req.body.name
			using : req.body.using.toString()

		#Given a status, get the dataset entity and put it inside status
		getDatasets = (pattern)=>
			deferred  = @App.Q.defer();
			console.log pattern.datasetID
			@App.Models.Dataset.findOne {_id : @App.objectID(pattern.datasetID)} , (err, _data)=>
				if !err
					if _data 
						delete pattern.datasetID
						data = pattern
						data.dataset = _data
						deferred.resolve data
					else
						deferred.resolve {}
				else
					deferred.reject(@App.sendAdminError req, res, err)
			return deferred.promise;
		getPatternStatuses = (status)=>
			defer = @App.Q.defer();
			promises = []
			resolvedPatterns = []
			for pattern in status.patterns
				promises.push getDatasets(pattern)
			@App.Q.allSettled(promises).then (results)=>
				for result in results
					if result.state is "fulfilled"
						resolvedPatterns.push result.value
					else
						defer.reject {}
				defer.resolve {"patterns" : resolvedPatterns,"statusValue": status.statusValue}
			return defer.promise;
		promises = []	
		for status in req.body.statuses
				promises.push getPatternStatuses(status)
				console.log "Getting datasets"

		@App.Q.allSettled(promises).then (results) =>
			datasets = []
			for result in results
				if result.state is "fulfilled"
					datasets.push result.value
			formula.statuses = datasets
		
			@App.Models.Formula.insert formula, (err, data)=>
				if !err
					if data 
						return @App.sendContent req, res, data
				else
					return @App.sendAdminError req, res, err
	getFormulas : (req, res)=>
		@App.Models.Formula.find({}).toArray (err, data)=>
			if !err
				if data
					return @App.sendContent req, res, data
				else
					return @App.sendError req, res, 404, "Did not find anything"
			else
				return @App.sendAdminError req, res, err 
	getFormula : (req, res)=>
		@App.Models.Formula.find({_id : @App.objectID(req.params.id)}).toArray (err, data)=>
			if !err
				if data
					return @App.sendContent req, res, data[0]
				else
					return @App.sendError req, res, 404, "Did not find anything"
			else
				return @App.sendAdminError req, res, err
	
 	
module.exports = Datasource