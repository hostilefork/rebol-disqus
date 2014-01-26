Rebol [
	Title: {Disqus API Client for Rebol}

	File: %disqus.reb
	Author: {HostileFork}
	Home: https://github.com/hostilefork/rebol-disqus

	Description: {
		This is a VERY early stage of implementing a wrapper around the
		Disqus API to be automated through Rebol.  It is beginning life
		with only two abilities initially: finding thread IDs from URLs,
		and posting comments to those URLs...optionally backdating them
		or making them appear to come from a guest account:

			http://disqus.com/api/docs/

		It was originally written only to be good enough to support the
		importation of comments from the old hostilefork.com to Disqus
		for blog.hostilefork.com - further improvements and pull
		requests are left as an exercise to the reader.  :-)

		There is no error handling, and if you reach an error then you
		will need to retry the API request using a browser tool like
		Web Developer Toolbar for Firefox, or Postman for Chrome.  This
		is another obvious area for improvement.
	}

	License: 'mit

	Settings: [
		forum: <forum> ;-- forum name from your Disqus dashboard
		api_key: <api-key> ;-- e.g. {T5hiSiS7AfakE1KEyBu9tGIVINgi7TasANeX1amPLEo4fwHATTheYL4oO5KLIke1}
		cookie: <cookie> ;-- log into Disqus, take from browser, put {in braces}
	]
]


;-- Christopher Ross-Gill's web form encoding routines
do http://reb4.me/r3/altwebform.r


;-- Bridge the as-yet-unmerged to mainline naming change :-/
changed-function: if 10 = length? spec-of :function [
	old-function: :function
	function: :funct
	unset 'funct
	true
]


;
; Disqus does dates as ISO-8601 dates, this is adapted from:
;
;      http://www.rebol.org/view-script.r?script=to-iso-8601-date.r
;
; I had to tweak to meet the specifications of date construct:
;
;     http://tools.ietf.org/html/rfc4287
;
to-iso8601-date: function [
	 {Converts a date! to a string which complies with the ISO 8602 standard.
	  If the time is not set on the input date, a default of 00:00 is used.}
	 
	the-date [date!]
		"The date to be reformatted"
	/timestamp
		{Include the timestamp}
][ 
	iso-date: copy ""

	if timestamp [
		either the-date/time [
			; the date has a time
			insert iso-date rejoin [
				"T"

				; insert leading zero if needed	            
				either the-date/time/hour > 9
					[the-date/time/hour]
					[join "0" [the-date/time/hour]]
				":"
				either the-date/time/minute > 9
					[the-date/time/minute]
					[join "0" [the-date/time/minute]]
				":"

				; Rebol only returns seconds if non-zero
				either the-date/time/second > 9 
					[to-integer the-date/time/second]
					[join "0" [to-integer the-date/time/second]]
				
				either the-date/zone = 0:00 [
					; UTC
					"Z"                           
				][
					rejoin [
						; + or - UTC
						either the-date/zone/hour > 0
							["+"]
							["-"]
						either  (absolute the-date/zone/hour) < 10
							[join "0" [absolute the-date/zone/hour]]
							[absolute the-date/zone/hour]
						{:}
						either the-date/zone/minute < 10
							[join "0" [the-date/zone/minute]]
							[the-date/zone/minute]
					]
				]
			] ; end insert  
		][
			; the date has no time
			iso-date: " 00:00:00Z" 
		]
	]
	 
	insert iso-date rejoin [
		join copy/part "000" (4 - length? to string! the-date/year)
			[the-date/year]
		"-"
		either the-date/month > 9
			[the-date/month]
			[join "0" [the-date/month]]
		"-"
		either the-date/day > 9
			[the-date/day]
			[join "0" [the-date/day]]
	 ] ; end insert

	return head iso-date   
]


disqus: context bind [
	logged-in-header: function [] [
		compose [
			Accept: {*/*}
			Accept-Encoding: {gzip,deflate,sdch}
			Accept-Language: {en-US,en;q=0.8}
			Connection: {keep-alive}
			Content-Type: {application/x-www-form-urlencoded; charset=UTF-8}
			Host: {disqus.com}
			Origin: {http://disqus.com}
			Cookie: (
				settings/cookie
			)
		]
	]


	thread-id-for-url: function [
		{Use the posts/list API query to get the thread ID for a URL}

		url [url!]
		/create {Allocates a thread if it does not yet exist.}
	] [
		data: compose [
			forum (settings/forum)
			api_key (settings/api_key)
			thread (rejoin [{link:} to string! url])
		]

		;-- Dehexing is necessary because the form encoded data
		;-- is being put as part of the URL, not in the payload (?)
		request: rejoin [
			http://disqus.com/api/3.0/threads/details dehex to-webform/prefix data
		]

		;-- If the read fails, it will throw an error
		response: try [read request]

		create-response: none

		;-- Should examine headers to get a specific "does not exist"
		;-- error before trying this.  Need response headers to know for
		;-- sure.  Follow up on:
		;--    http://stackoverflow.com/questions/21226498/
		if all [
			create
			error? response
		] [
			page-data: try [read url]

			if error? page-data [
				print ["Could not read page to get title from" url]
				quit
			]

			unless parse to string! page-data [
				thru {<title>} copy page-title to {</title>} to end
			] [
				print ["No <title> found when page retrieved from" url]
				quit
			]

			create-data: compose [
				forum (settings/forum)
				api_key (settings/api_key)
				url (to string! url)
				title (title)
			]

			create-response: try [
				write http://disqus.com/api/3.0/threads/create.json compose/only [
					post (logged-in-header)
					(to-webform create-data)
				]
			]
			
			if all [
				not error? create-response
				find to string! create-response {"id":"}
			] [
				print ["THREAD CREATED"]
				response: create-response
			]
		]

		either all [
			not error? response
			parse to string! response [
				thru {"id":"} copy thread-id to {"} to end
			]
		] [
			print ["THREAD ID RETRIEVED:" thread-id]
		] [
			print [{ERROR while reading thread id for} url]
			print [{Request was:} lf request]
			print [{Response was:} lf to string! response]
			if create-response [
				print [{Creation was attempted and failed}]
				print [{Create request data was:} lf to-webform create-data]
				print [{Create response was:} lf to string! create-response]
			]
			quit
		]

		return to integer! thread-id
	]


	post-comment: function [
		{Posts a comment to a thread, either as a guest or as an authenticated
		user.  Can optionally backdate the thread if the cookie has been set
		and validates as a logged-in user for the forum.}

		thread [url! integer!]
		message [string!]
		/guest
			author_name [string!]
			author_email [email!]
			author_url [url! none!]
				{API accepts a URL for guest posts, but Disqus *won't* display it} 
		/authenticated
			access_token [string!]
		/timestamp
			date [date!]
		/create {Create the thread if it doesn't exist already}
	] [
		unless (to logic! authenticated) xor (to logic! guest) [
			print "Call post-comment with one (and only one) of /authentication or /guest"
			quit
		]

		either create [
			;-- does not make sense to create a thread if we have
			;-- an id# for it already
			assert [url? thread]

			thread-id: thread-id-for-url/create thread
		] [
			thread-id: either url? thread [
				thread-id-for-url thread
			] [
				thread
			]
		]

		data: compose [
			api_key (settings/api_key)
			thread (thread-id)
			message (message)
		]

		append data case [
			guest [
				compose [
					author_name (author_name)
					author_email (to string! author_email)
					(either author_url [
						compose [author_url (to string! author_url)]
					] [
						[]
					])
				]
			]

			authenticated [
				compose [
					access_token (access_token)
				]
			]
		]

		if timestamp [
			;-- Times are assumed UTC, zones make Disqus choke circa Jan-2014
			date/zone: none
			append data compose [
				date (to-iso8601-date/timestamp date)
			]
		]

		response: try [
			write http://disqus.com/api/3.0/posts/create.json compose/only [
				post (logged-in-header)
				(to-webform data)
			]
		]

		if any [
			error? response
			not find to string! response {"code":0}
		] [
			print [{ERROR while posting comment to thread:} thread]
			print [{Request x-www-form-urlencoded was:} lf to-webform data]
			print [{Response was:} lf to string! response]
			quit
		]
	]
] context [ ;-- Internals
	settings: make context [
		forum: api_key: cookie: none
	] any [
		system/script/args
		system/script/header/settings
	]
]


;-- Restore funct/function expectation of caller
if changed-function [
	funct: :function
	function: :old-function
]
