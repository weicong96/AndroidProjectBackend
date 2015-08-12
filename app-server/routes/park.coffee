request = require("request")
class Parks
	
	constructor : (@App)->
		routeName= "park"
		@App.router.post "/#{routeName}", @postPark
		@App.router.get "/#{routeName}", @listParks
		@App.router.get "/#{routeName}/:id", @getParksById
		@App.router.get "/#{routeName}/latlng/:q", @getLatLng
		@geoCode = require("geocoder")
	getParksById : (req, res, next)=>
		@App.Models.Park.findOne {_id : @App.objectID(req.params.id)}, (err, data)=>
			if !err 
				if data
					data.name = data.parkName[0]
					delete data.parkName
					return @App.sendContent req, res, data
			else
				return @App.sendAdminError req, res, err

	postPark : (req, res, next)=>
		park = 
			name : req.body.name
			address : req.body.address
			lat : req.body.lat
			lng : req.body.lng
		@App.Models.Park.insert park, (err, data)=>
			if !err
				if data
					console.log data
					return @App.sendContent req, res, data[0]
				else
					return @App.sendError req, res, 404, "Not able to insert"
			else
				return @App.sendAdminError req, res, err
	listParks : (req, res, next)=>
		@App.Models.Park.find({}).toArray (err, cursor)=>
			if !err
				if cursor
					for result in cursor 
						result.name = result.parkName[0]
						delete result.parkName 
					return @App.sendContent req, res, cursor
				else
					return @App.sendError req, res, 404, "Cannot find anything"
			else
				return @App.sendAdminError req, res, err 
	getLatLng : (req, res, next)=>
		address = req.params.q 
		if address.indexOf "SG" is -1
			address = address+", SG"
		@geoCode.geocode address , (err,data)=>
			if !err
				if data
					return @App.sendContent req, res, data
				else
					return @App.sendError req, res, 402, "Could not geocode data"
			else
				return @App.sendAdminError req, res, err
 		
module.exports = Parks