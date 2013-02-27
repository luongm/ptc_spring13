from httplib import HTTPConnection
from urllib import urlencode
from time import time
import web
import sys

servers = ["ec2-184-169-190-253.us-west-1.compute.amazonaws.com",
           "ec2-184-169-210-186.us-west-1.compute.amazonaws.com",
           "ec2-184-169-254-236.us-west-1.compute.amazonaws.com"]
other_servers_index = [0,1,2]
other_servers_index.remove(int(sys.argv[2]))
port = int(sys.argv[1])

urls = (
    '/start_auction', 'start_auction',
    '/bid', 'bid',
    '/status', 'status',
    '/winner', 'winner',
    '/rst', 'rst',

    '/update_new_auction', 'update_new_auction',
    '/update_bid', 'update_bid',
    )

app = web.application(urls, globals())

auctions    = {}    # {auction_name: end_time}
winners     = {}    # {auction_name: current_winning_client}
winning_bid = {}    # {auction_name: current_winning_bid}

class start_auction:
  def POST(self):
    try:
      name     = web.input().name
      end_time = int(float(web.input().end_time))
    except:
      return

    if not name or name in auctions or not end_time or end_time < time():
      return

    auctions[name] = end_time
    winning_bid[name] = -1

    # forward updates to other servers
    for i in other_servers_index:
      conn = HTTPConnection(servers[i], port)
      params = urlencode({"name":name, "end_time":end_time})
      conn.request("POST", "/update_new_auction", params)

class update_new_auction:
  def POST(self):
    name = web.input().name
    end_time = int(web.input().end_time)

    # if name in auctions:
      # TODO ignored?

    auctions[name] = end_time
    winning_bid[name] = -1

class bid:
  def POST(self):
    name   = web.input().name
    client = web.input().client
    bid    = int(web.input().bid)

    if name not in auctions or bid < winning_bid[name] or time() > auctions[name]:
      return
    if bid == winning_bid[name] and client > winners[name]:
      return

    winners[name] = client
    winning_bid[name] = bid

    # forward updates to other servers
    for i in other_servers_index:
      conn = HTTPConnection(servers[i], port)
      params = urlencode({"name":name, "client":client, "bid":bid})
      conn.request("POST", "/update_bid", params)

class update_bid:
  def POST(self):
    name   = web.input().name
    client = web.input().client
    bid    = int(web.input().bid)

    if bid == winning_bid[name] and client > winners[name]:
      for i in other_servers_index:
        conn = HTTPConnection(servers[i], port)
        params = urlencode({"name":name, "client":winners[name], "bid":bid})
        conn.request("POST", "/update_bid", params)
      return "My client has better bid, re-update other servers"

    winners[name] = client
    winning_bid[name] = bid

class status:
  def GET(self):
    name = web.input().name
    
    if name not in auctions:
      return

    if name in winners:
      return winners[name]
    return "UNKNOWN"

class winner:
  def GET(self):
    name = web.input().name
    
    if name not in auctions:
      return

    if name in winners and time() > auctions[name]:
      return winners[name]
    return "UNKNOWN"

class rst:
  def POST(self):
    auctions.clear()
    winners.clear()
    winning_bid.clear()

if __name__ == "__main__":
  app.run()
