//
//  InstagramComms.swift
//  Kitura-Starter
//
//  Created by william donner on 2/20/17.
//
//

import Foundation
import Kitura
import LoggerAPI
import KituraRequest
import IgBluCommons

enum Instgr {
    case mediaLikes(String,String)
    case mediaComments(String,String)
    case userInfo(String,String)
    case relationship(String,String)
    case mediaRecent(String,String)
    
    case mediaRecentAboveMin(String,String,String )//token,min_id,max_id
    case mediaRecentBelowMax(String,String,String )//token,min_id,max_id
    case mediaRecentInRange(String,String,String,String)//token,min_id,max_id
    
    case following(String,String) // deprecated by instagram ...soon
    case followedBy(String,String) // deprecated by instagram ...
    
    case taginfo(String,String)
    case tagrecent(String,String)
    // MARK: apart from IG Oauth all the various IG api calls are vectored thru here
    
    var uri: (path: String, parameters: [String:Any] ) {
        
        let result: (path: String, parameters: [String:Any] ) = {
            switch self {
                
                
            case .relationship (let userID, let accessToken):
                let pathString = "/v1/users/" + userID + "/relationship"
                return (pathString, ["access_token": accessToken     ])
                
            case .userInfo (let userID, let accessToken):
                let pathString = "/v1/users/" + userID
                return (pathString, ["access_token": accessToken   ])
                
            case .mediaLikes (let mediaID, let accessToken):
                
                let pathString = "/v1/media/" + mediaID + "/likes"
                return (pathString, ["access_token": accessToken   ])
                
            case .mediaComments (let mediaID, let accessToken):
                
                let pathString = "/v1/media/" + mediaID + "/comments"
                return (pathString, ["access_token": accessToken   ])
                
            case .mediaRecent (let userID , let accessToken ):
                
                let pathString = "/v1/users/" + userID + "/media/recent"
                return (pathString, ["access_token": accessToken   ])
                
            case .mediaRecentAboveMin ( _ , let accessToken, let minID  ):
                let userID = "self"
                let pathString = "/v1/users/" + userID + "/media/recent"
                return (pathString, ["access_token": accessToken  ,"min_id":minID    ])
                
            case .mediaRecentBelowMax ( _ , let accessToken, let maxID ):
                let userID = "self"
                let pathString = "/v1/users/" + userID + "/media/recent"
                return (pathString, ["access_token": accessToken  , "max_id":maxID    ])
                
            case .mediaRecentInRange ( _ , let accessToken, let minID, let maxID ):
                let userID = "self"
                let pathString = "/v1/users/" + userID + "/media/recent"
                return (pathString, ["access_token": accessToken  ,"min_id":minID  ,"max_id":maxID    ])
                
            case .following ( _  , let accessToken):
                let userID = "self"
                let pathString = "/v1/users/" + userID + "/follows"
                return (pathString, ["access_token": accessToken  ])
                
            case .followedBy ( _ , let accessToken ):
                let userID = "self"
                let pathString = "/v1/users/" + userID + "/followed-by"
                return (pathString, ["access_token": accessToken  ])
                
                
            case .taginfo( let tagName  , let accessToken  ):
                
                let pathString = "/v1/tags/" + tagName
                return (pathString, ["access_token": accessToken    ])
                
                
            case .tagrecent( let tagName  , let accessToken  ):
                
                let pathString = "/v1/tags/" + tagName  + "/media/recent"
                return (pathString, ["access_token": accessToken    ])
                
            }
        }()
        
        
        return result
    }
}


// to call instagram, come thru here


//     execInstagramAPIGET(Instgr.mediaComments("a", "b").uri)

//TODO: do something about this - move it into globals
var igApiCount = 0
func execInstagramAPIGET(_ urlargs:(String,[String:Any]),  completion:@escaping (Int,Data?)->()) {
    igApiCount += 1
    let url =  "https://api.instagram.com" + urlargs.0
    KituraRequest.request(.get,
                          url,
                          parameters: urlargs.1,
                          encoding: URLEncoding.default).response { req, resp, iidata, error in
                            guard error == nil else {
                                Log.error("error from instagram \(error!)")
                                completion(404,nil)
                                return
                            }
                            
                            completion(200,iidata!)
    }
}

func basicDrain(id:String, token:String, completion:@escaping (Int,String,[String:Any])->()) {
    let dateFormatter = DateFormatter()
    var jdict:[String:Any] = [:]
    var ebuf = ""
    func eprint(_ s:String) {
        ebuf.append(s)
        ebuf.append("\n")
    }
    Log.warning("Running Basic API Calls to Load DB for user \(id)")
    let starttime = Date()
    let startapicount = igApiCount
    
    // get all the background stuff and store as one big json in one cycle
    execInstagramAPIGET(Instgr.userInfo (id, token).uri){code1,data1 in
        // parse userinfo
        
        if let outer = try? JSONSerialization.jsonObject(with: data1!, options: .allowFragments) as? [String: Any],
            let meta =  outer?["meta"] as? [String:Any],
            let code = meta ["code"] as? Int {
            guard  code == 200 else {
                    Log.error("bad return \(code) from execInstagramAPIGET")
                    return
                }
            
            if  let data = outer?["data"] as?  [String: Any ]   ,
                let id = data  ["id"] ,
                let fn = data  ["username"],
                let counts = data ["counts"] as? [String: Any],
                let cmedia = counts["media"],
                let cfollows = counts["follows"],
                let cfollowedby = counts["followed_by"] {
                jdict["userinfo"] = ["id":id,"fn":fn,"media-count":cmedia,"follows-count":cfollows,"followed-by-count":cfollowedby]
                
                eprint(" userInfo id:\(id)-\(fn) meida:\(cmedia) follows:\(cfollows) by:\(cfollowedby)")
            }
            
            //this call is kind of silly since it is always relative to "self"
            
            Log.warning("Running relationship API Calls  for user \(id)")
            execInstagramAPIGET(Instgr.relationship (id, token).uri){code2,data2 in
                // parse relationship
                
                if let outer = try? JSONSerialization.jsonObject(with: data2!, options: .allowFragments) as? [String: Any],
                    let meta =  outer?["meta"] as? [String:Any],
                    let code = meta ["code"] as? Int {
                    
                    guard  code == 200 else {
                        Log.error("bad return \(code) from execInstagramAPIGET")
                        return
                    }
                 if  let data = outer?["data"] as?  [String: Any ]   ,
                        let o = data  ["outgoing_status"] ,
                        let i = data  ["incoming_status"] {
                        eprint("  relationship out:\(o) in:\(i) code:\(code2) ")
                    }
                }
                
                Log.warning("Running following API Calls  for user \(id)")
                execInstagramAPIGET(Instgr.following (id, token).uri){code3,data3 in
                    if let outer = try? JSONSerialization.jsonObject(with: data3!, options: .allowFragments) as? [String: Any],
                        let meta =  outer?["meta"] as? [String:Any],
                        let code = meta ["code"] as? Int {
                        
                        guard  code == 200 else {
                            Log.error("bad return \(code) from execInstagramAPIGET")
                            return
                        }
                        
                        var jblks:[[String:String]] = []
                        if  let data = outer?["data"] as? [[String: Any ]]  {
                            for subjson in data {
                                
                                let u = subjson ["username"] as? String  ?? ""
                                let pic = subjson ["profile_picture"] as? String   ?? ""
                                let fn = subjson ["full_name"] as? String  ?? ""
                                let id = subjson ["id"] as? String ?? ""
                                jblks.append(["id" :id,"fn":fn,"un":u, "pic":pic])
                                eprint(" following:  \(id)-\(u)")
                            }
                            
                        }
                        jdict["following"] = jblks
                    }
                    
                    // after processing all elements in following,  still in  closure
                    
                    Log.warning("Running followedby API Calls  for user \(id)")
                    execInstagramAPIGET(Instgr.followedBy (id, token).uri){code4,data4 in
                        
                        if let outer = try? JSONSerialization.jsonObject(with: data4!, options: .allowFragments) as? [String: Any],
                            let meta =  outer?["meta"] as? [String:Any],
                            let code = meta ["code"] as? Int   {
                            
                            guard  code == 200 else {
                                Log.error("bad return \(code) from execInstagramAPIGET")
                                return
                            }
                            var jblks:[[String:String]] = []
                            if  let data = outer?["data"] as? [[String: Any ]]  {
                                for subjson in data {
                                    
                                    let u = subjson ["username"] as? String ?? ""
                                    let pic = subjson ["profile_picture"] as? String ?? ""
                                    let fn = subjson ["full_name"] as? String ?? ""
                                    let id = subjson ["id"]  as? String ??  ""
                                    jblks.append(["id" :id,"fn":fn,"un":u, "pic":pic])
                                    eprint(" followedBy: \(id)-\(u)")
                                }
                            }
                            
                            jdict["followed-by"] = jblks
                        }
                        
                        // after processing all elements in followed by,  still in  closure
                        var mrblks:[[String:Any]] = []
                        // get our own recent postings
                        
                        Log.warning("Running mediaRecent API Calls  for user \(id)")
                        execInstagramAPIGET(Instgr.mediaRecent ("self", token).uri){code6,data6 in
                            var dictchunk : [String:Any] = [:]
                            // works on self
                            if let outer = try? JSONSerialization.jsonObject(with: data6!, options: .allowFragments) as? [String: Any],
                                let meta =  outer?["meta"] as? [String:Any],
                                let code = meta ["code"] as? Int  {
                                guard  code == 200 else {
                                    Log.error("bad return \(code) from execInstagramAPIGET")
                                    return
                                }
                                if  let data = outer?["data"] as? [[String: Any ]]  {
                                    for subjson in data {
                                        
                                        let u = subjson ["type"] ?? ""
                                        let p = subjson ["filter"] ?? ""
                                        let link = subjson ["link"] ?? ""
                                        let mediaid:String  = subjson ["id"] as! String? ?? ""
                                        var foundimage = ""
                                        if let images =   subjson ["images"] as? [String:Any] ,
                                            let thumbnail = images ["thumbnail"] as? [String:Any] {
                                            if let url = thumbnail["url"] as? String {
                                                foundimage = url
                                            }
                                        }
                                        
                                        //let tags = subjson["tags"] ?? ""
                                        if let cap = subjson ["caption"] as? [String:Any] ,
                                            let ct = cap ["created_time"] as? String ,
                                            let text = cap ["text"] as? String ,
                                            let likes = subjson ["likes"] as?  [String:Any],
                                            let countlikes = likes["count"] as? Int,
                                            let comments = subjson ["comments"] as?  [String:Any],
                                            let countcomments = comments["count"] as? Int{
                                            
                                            if  let timeResult = (Double(ct)) {
                                                let date = Date(timeIntervalSince1970: timeResult)
                                                
                                                dateFormatter.timeStyle = DateFormatter.Style.medium //Set time style
                                                dateFormatter.dateStyle = DateFormatter.Style.medium //Set date style
                                                dateFormatter.timeZone = TimeZone.current
                                                let localDate = dateFormatter.string(from: date)
                                                eprint(" posted \(u) likes:\(countlikes) comments:\(countcomments)  \(localDate)  \(text)\n      filter:\(p)  \(link) ")
                                                
                                                dictchunk = ["ct":localDate,"text":text,
                                                             "likes-count":countlikes,"comments-count":countcomments,"filter":p,"imgurl":foundimage,"link":link ]
                                                
                                            }
                                            
                                        }
                                        if mediaid !=  ""  {
                                            execInstagramAPIGET(Instgr.mediaComments(mediaid, token).uri){code9,data9  in
                                                var commentchunks:[[String:Any]] = []
                                                if let outer = try? JSONSerialization.jsonObject(with: data9!, options: .allowFragments) as? [String: Any],
                                                    let meta =  outer?["meta"] as? [String:Any],
                                                    let code = meta ["code"] as? Int {
                                                    guard  code == 200 else {
                                                        Log.error("bad return \(code) from execInstagramAPIGET")
                                                        return
                                                    }
                                                    
                                                    if  let data = outer?["data"] as? [[String: Any ]]  {
                                                        
                                                        for subjson in data {
                                                            
                                                            let p = subjson ["text"] ?? ""
                                                            let commentid = subjson ["id"] ?? ""
                                                            
                                                            if  let from = subjson ["from"] as? [String:String],
                                                                let username = from["username"],
                                                                    let pic = from["profile_picture"],
                                                                let userid = from["id"] {
                                                                eprint("   commentor: \(userid)-\(username)  comment: \(p) from: \(commentid)")
                                                                let commentchunk = ["from":commentid,"comment": "\(p)",
                                                                    "userid":userid,"u":username,"pic":pic ]
                                                                commentchunks.append(commentchunk)
                                                            }
                                                        }// for
                                                    }
                                                    dictchunk["comments"] = commentchunks
                                                }// has any data,still in closure
                                                execInstagramAPIGET(Instgr.mediaLikes(mediaid, token).uri){code5,data5  in
                                                    
                                                    var likerchunks:[[String:Any]] = []
                                                    if let outer = try? JSONSerialization.jsonObject(with: data5!, options: .allowFragments) as? [String: Any],
                                                        let meta =  outer?["meta"] as? [String:Any],
                                                        let code = meta ["code"] as? Int   {
                                                        guard  code == 200 else {
                                                            Log.error("bad return \(code) from execInstagramAPIGET")
                                                            return
                                                        }
                                                        if  let data = outer?["data"] as? [[String: Any ]]  {
                                                            
                                                            for subjson in data {
                                                                
                                                                let un = subjson ["username"] ?? ""
                                                                let likerid = subjson ["id"] ?? ""
                                                                
                                                                eprint("   liker: \(likerid)-\(un)")
                                                                
                                                                let likerchunk = ["from":likerid,"u":un ]
                                                                likerchunks.append(likerchunk)
                                                                
                                                            }// for loop
                                                        }// has data
                                                    }// serialized ok
                                                    dictchunk["likes"] = likerchunks
                                                    mrblks.append(dictchunk)
                                                    
                                                }// end of media likes closure
                                            }//end of media comments for this media
                                            
                                            
                                        }// did serialize properly
                                        
                                        
                                        jdict["media-recent"] = mrblks
                                        
                                    }//end of for loop thru all data
                                    
                                    ///////////// THIS IS WHERE IT ENDS ??????????
                                    /// wrap up
                                    let elapsed = Date().timeIntervalSince(starttime) //secs
                                    let prelap = String(format:"%0.2f secs",elapsed)
                                    let  apicount = igApiCount - startapicount
                                    eprint("Finished Running \(apicount) API Calls to Load DB in \(prelap) for user \(id)")
                                    
                                    let fdict:[String:Any] = ["api-calls":apicount,"elapsed-secs":prelap,"user":id,"operation":"full-dbload","data":jdict]
                                    completion(200,ebuf,fdict)
                                    
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
