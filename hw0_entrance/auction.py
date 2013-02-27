# ec2-54-241-78-34.us-west-1.compute.amazonaws.com

import web
from time import time

urls = (
    '/start_auction', 'start_auction',
    '/bid', 'bid',
    '/status', 'status',
    '/winner', 'winner',
    '/rst', 'rst',
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

    if not name or name in auctions.keys() or not end_time or end_time < time():
      return

    auctions[name] = end_time
    winning_bid[name] = -1

class bid:
  def POST(self):
    try:
      name   = web.input().name
      client = web.input().client
      bid    = int(web.input().bid)
    except:
      return

    if name not in auctions or bid < winning_bid[name] or time() > auctions[name]:
      return
    if bid == winning_bid[name] and client > winners[name]:
      return

    winners[name] = client
    winning_bid[name] = bid

class status:
  def GET(self):
    try:
      name = web.input().name
    except:
      return
    
    if name not in auctions:
      return

    if name in winners:
      return winners[name]
    return "UNKNOWN"

class winner:
  def GET(self):
    try:
      name = web.input().name
    except:
      return
    
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
