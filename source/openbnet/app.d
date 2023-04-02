module openbnet.app;

import openbnet.types;
import vibe.d;
import std.functional : toDelegate;
import gogga;
import core.stdc.stdlib : getenv;
import std.string : fromStringz;
import std.net.curl : post, HTTP;

private GoggaLogger logger;

static this()
{
	logger = new GoggaLogger();
	logger.enableDebug();

	version(release)
	{
		logger.disableDebug();
	}
}

private string rpcEndpoint = "https://apiuser:password@127.0.0.1:8001/api";

public class Network
{
	public string name;
	public string logo;
	public string description;
}

// TODO: A fetch channel should populate with users list inside it

/** 
 * Fetches the statistics information by making the `stats.get`
 * request and then parsing the results
 *
 * Returns: an instance of Stats containing the information
 */
private Stats fetchStats()
{
	Stats stats;

	/** 
	 * Make the request
	 *
	 * `"jsonrpc": "2.0", "method": "stats.get", "parans" : {}, "id": 123`
	 */
	string[string] postData;
	postData["jsonrpc"] = "2.0";
	postData["method"] = "stats.get";

	import std.json;
	JSONValue params;
	postData["params"] = params.toString();


	postData["id"] = JSONValue(123).toString();

	string response = cast(string)post(rpcEndpoint, postData);

	/**
	 * Parse the response
	 */
	JSONValue responseJSON = parseJSON(response);
	stats = Stats.fromJSON(responseJSON);

	return stats;
}

private Channel[] fetchChannels()
{
	Channel[] fetchedChannels;

	/** 
	 * Make the request
	 *
	 * `"{jsonrpc": "2.0", "method": "channel.list", "params": {}, "id": 123}`
	 */
	import std.json;
	JSONValue postData;
	postData["jsonrpc"] = "2.0";
	postData["method"] = "channel.list";

	
	JSONValue params;
	postData["params"] = params.toString();

	postData["id"] = JSONValue(123).toString();
	

	// FIXME: Why does DLog crash with this?
	// logger.log("Post data JSON: ", postData.toPrettyString());

	string response = cast(string)post(rpcEndpoint, postData.toPrettyString());

	/**
	 * Parse the response
	 */
	JSONValue responseJSON = parseJSON(response);
	// logger.log("Got: "~responseJSON.toPrettyString());
	import std.stdio;
	writeln(responseJSON.toPrettyString());
	foreach(JSONValue curChannel; responseJSON["result"]["list"].array())
	{
		fetchedChannels ~= Channel.fromJSON(curChannel);
	}

	

	return fetchedChannels;
}

private Server[] fetchServers()
{
	Server[] fetchedServers;

	/** 
	 * Make the request
	 *
	 * `{"jsonrpc": "2.0", "method": "server.list", "params": {}, "id": 123}`
	 */
	import std.json;
	JSONValue postData;
	postData["jsonrpc"] = "2.0";
	postData["method"] = "server.list";

	
	JSONValue params;
	postData["params"] = params.toString();

	postData["id"] = JSONValue(123).toString();

	string response = cast(string)post(rpcEndpoint, postData.toPrettyString());

	/**
	 * Parse the response
	 */
	JSONValue responseJSON = parseJSON(response);
	foreach(JSONValue curServer; responseJSON["result"]["list"].array())
	{
		fetchedServers ~= Server.fromJSON(curServer);
	}


	return fetchedServers;
}

private ChannelInfo fetchChannelInfo(string channel)
{
	ChannelInfo fetchedChannelInfo;

	/** 
	 * Make the request
	 *
	 * `{"jsonrpc": "2.0", "method": "channel.get", "params": {"channel":"#<channel>"}, "id": 123}`
	 */
	 import std.json;
	JSONValue postData;
	postData["jsonrpc"] = "2.0";
	postData["method"] = "channel.get";

	
	JSONValue params;
	params["channel"] = channel;
	postData["params"] = params;

	postData["id"] = 123;

	string response = cast(string)post(rpcEndpoint, postData.toPrettyString());

	/**
	 * Parse the response
	 */
	JSONValue responseJSON = parseJSON(response);
	fetchedChannelInfo = ChannelInfo.fromJSON(responseJSON["result"]["channel"]);


	return fetchedChannelInfo;
}

void channelListHandler(HTTPServerRequest req, HTTPServerResponse resp)
{
	/* Fetch the channels */
	Channel[] channels = fetchChannels();

	// TODO: Add actual network here
	Network network = new Network();

	resp.render!("channels.dt", network, channels);
}

void serverListHandler(HTTPServerRequest req, HTTPServerResponse resp)
{
	/* Fetch the servers */
	Server[] servers = fetchServers();

	// TODO: Add actual network here
	Network network = new Network();

	resp.render!("servers.dt", network, servers);
}

void channelInfoHandler(HTTPServerRequest req, HTTPServerResponse resp)
{
	// TODO: Add actual network here
	Network network = new Network();

	/* Extract the parameters */
	auto params = req.query;

	logger.debug_(params);

	/* Extract name parameter */
	if(params.get("name") !is null) // TODO: Ensure channel name is not empty string
	{
		/* Extract the channel name */
		string channelName = strip(params["name"]);

		

		/* Fetch the channel info */
		ChannelInfo channelInfo = fetchChannelInfo(channelName);


		resp.render!("channelinfo.dt", channelInfo, network);

	}
	/* If not found, throw an error */
	else
	{
		logger.error("The channel name parameter is not present");
		throw new HTTPStatusException(HTTPStatus.badRequest, "Missing channel name parameter");
	}

	// TODO: Ensure we have a "name" parameter, if not throw an HTTP error
}

void homeHandler(HTTPServerRequest req, HTTPServerResponse resp)
{
	// TODO: Add actual network here
	Network network = new Network();

	/* Fetch the network statistics */
	Stats stats = fetchStats();

	resp.render!("home.dt", network, stats);
}

void errorHandler(HTTPServerRequest req, HTTPServerResponse resp, HTTPServerErrorInfo error)
{
	// TODO: FInish error page
	Network network = new Network();

	auto request = req;
	resp.render!("error.dt", error, request, network);
}

void main()
{
	logger.info("Welcome to OpenBNET!");

	
	rpcEndpoint = cast(string)fromStringz(getenv("RPC_ENDPOINT"));
	if(rpcEndpoint == null)
	{
		logger.error("The environment variable 'RPC_ENDPOINT' was not specified");
		return;
	}
	logger.info("Using RPC endpoint '"~rpcEndpoint~"'");

	HTTPServerSettings httpSettings = new HTTPServerSettings();
	httpSettings.bindAddresses = ["::"];
	httpSettings.port = 8002;

	
	httpSettings.errorPageHandler = toDelegate(&errorHandler);

	URLRouter router = new URLRouter();

	router.get("/", &homeHandler);
	router.get("/channels", &channelListHandler);
	router.get("/channelinfo", &channelInfoHandler);
	router.get("/servers", &serverListHandler);

	// Setup serving of static files
	router.get("/assets/table.css", serveStaticFile("assets/table.css"));
	router.get("/assets/open_bnet_banner.png", serveStaticFile("assets/open_bnet_banner.png"));
	router.get("/favicon.ico", serveStaticFile("assets/b_hash_logo.png"));

	listenHTTP(httpSettings, router);

	runApplication();
}