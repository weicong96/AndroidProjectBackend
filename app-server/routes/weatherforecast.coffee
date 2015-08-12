
request = require("request")
class WeatherForecast
    constructor: (@App)->  
        routeName = "forecast"

        @App.router.get "/#{routeName}", @getWeatherForecast
    #Input :
    #       query:
    #           lat double  
    #           lng double
    getWeatherForecast:(req, res)=>
        urlName = "http://www.nea.gov.sg/api/WebAPI?dataset=nowcast&keyref=781CF461BB6606ADEA6B1B4F3228DE9DE7BFA37A1F9F416F"
        items = []
        request urlName, (error, response)=>
            parseString = require('xml2js').parseString;
            parseString response.body , (err, result)=>
                for element in result.channel.item[0].weatherForecast
                    for singleEntry in element["area"]
                        singleEntry =  singleEntry["$"]
                        distance = @getDistanceBtwnTwoPoints parseFloat(singleEntry.lat), parseFloat(singleEntry.lon), parseFloat(req.query.lat), parseFloat(req.query.lng)
                        
                        items.push {distance : distance, info : singleEntry} 
                distances = []
                items.every (element, index, array)=>
                    distances.push element.distance
                lowestDistance = 999
                lowestIndex = -1
                for value, index in distances
                    if lowestDistance > value 
                        lowestDistance = value
                        lowestIndex = index
                if lowestIndex isnt -1
                    return @App.sendContent req, res, items[lowestIndex]

    getDistanceBtwnTwoPoints : (lat1, lon1, lat2, lon2) =>
        deg2rad = (deg)->    
            return deg * (Math.PI/180)
        R = 6371
        dLat = deg2rad(lat2 - lat1)
        dLon = deg2rad(lon2 - lon1)
        a = Math.sin(dLat/2) * Math.sin(dLat/2) + Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * Math.sin(dLon/2) * Math.sin(dLon/2)
        c = 2 * Math.atan2(Math.sqrt(a) , Math.sqrt(1-a))
        d = R * c

        return d
        
module.exports = WeatherForecast