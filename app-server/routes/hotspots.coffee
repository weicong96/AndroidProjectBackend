geojson = require("togeojson")
fs = require("fs")
jsdom = require("jsdom").jsdom
ObjectId = require('mongodb').ObjectID;
moment = require("moment")
class Hotspots 
    constructor : (@App)->
        routeName = "hotspots"

        @App.router.get "/#{routeName}", @getHotspotDataNew
    

    getDistanceFromLatLonInKm : (lat1,lon1,lat2,lon2) =>
        R = 6371; #Radius of the earth in km
        dLat = @deg2rad(lat2-lat1);  #deg2rad below
        dLon = @deg2rad(lon2-lon1); 
        a = 
            Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(@deg2rad(lat1)) * Math.cos(@deg2rad(lat2)) * 
            Math.sin(dLon/2) * Math.sin(dLon/2); 
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); 
        d = R * c; # Distance in km
        return d;

    deg2rad : (deg)=> 
      return deg * (Math.PI/180)
    objectIdWithTimestamp : (date)=>
        return ObjectId.createFromTime date.getTime()/1000
    getHotspotDataNew : (req, res)=>
        parkid = req.query.parkid
        conditions = {}
        start = req.query.start
        end = req.query.end
        if start and end
            start = new Date(parseInt(start))
            end = new Date(parseInt(end))
            
            if !(start > end)
                return @App.sendError req, res, 400, "Start should be more than end"
            conditions = {appearedOn : {$gt : end, $lt : start}}
        else
            start = new Date()
            end = new Date(new Date().getTime() - 2 * 24 * 60 * 60 * 1000)

            #conditions = {appearedOn : {$gt : end, $lt : start}}
            conditions = {}
        console.log conditions
        findPark = (parkid)=>
            defer = @App.Q.defer();
            if !parkid
                defer.resolve null
            @App.Models.Park.findOne { _id : @App.objectID(parkid)}, (err,doc)=>
                if doc
                    defer.resolve doc
                else
                    defer.resolve null
            return defer.promise

        @App.Models.HotspotHistory.find(conditions).toArray (err,hotspots)=>
            result = []
            findPark(req.query.parkid).then (park)=>
                for hotspot in hotspots
                    distDiff = -1
                    if park isnt null
                        distDiff = @getDistanceFromLatLonInKm(park["lat"], park["lng"], hotspot["lat"], hotspot["lng"]) 
                    if (park and  distDiff < 2.3) or (park is null)
                        addToResult = {}
                        addToResult["_id"] = hotspot["_id"]
                        addToResult["feature"] = {lat : hotspot["lat"], lng : hotspot["lng"]} 
                        addToResult["appearedOn"] = hotspot["appearedOn"]
                        addToResult["disappearedOn"] = hotspot["disappearedOn"]
                        addToResult["type"] = hotspot["type"]
                        addToResult["description"] = hotspot["description"]
                        if distDiff isnt -1
                            addToResult["distDiff"] = distDiff
                        addToResult["differenceTime"] = moment(hotspot["appearedOn"]).fromNow()

                        result.push addToResult
                return @App.sendContent req, res, result
   
module.exports = Hotspots