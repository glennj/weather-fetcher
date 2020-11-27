"
Object subclass: #WttrIn.
WttrIn instanceVariableNames: 'city httpClient'.
WttrIn comment: 'I fetch weather from http://wttr.in
See https://github.com/chubin/wttr.in'.
"
PackageLoader fileInPackage: 'NetClients'.

Namespace current: Jackman [
Namespace current: Jackman.Weather [

Object subclass: WttrIn [
    |city httpClient|
    <comment: '
    I fetch weather from http://wttr.in
    See https://github.com/chubin/wttr.in
    '>
    <import: NetClients.HTTP>

    WttrIn class >> new [
        <category: 'instance creation'>
        ^ super new initialize.
    ]

    WttrIn class >> city: aString [
        <category: 'instance creation'>
        ^ (self new) city: aString; yourself.
    ]

    initialize [
        <category: 'initialization'>
        httpClient := HTTPClient connectToHost: 'wttr.in'.
    ]

    city: aString [
        <category: 'initialization'>
        city := aString.
    ]

    printOn: aStream [
        <category: 'printing'>
        super printOn: aStream.
        aStream nextPutAll: ' for city ', city.
    ]

    current [
        <category: 'weather'>
        ^ self get: city
    ]

    moon [
        <category: 'weather'>
        ^ self get: 'moon'
    ]

    get: what [
        | uri body |
        <category: 'weather'>
        uri := '/', what.
        body := WriteStream on: (String new: 4096).
        httpClient 
            get: uri
            requestHeaders: #('User-Agent: curl')
            into: body.
        ^ body contents
    ]
]

]
]
