import unittest
from httplib import HTTPConnection
from urllib import urlencode
from time import time, sleep

PORT = 8080
singly_server = "ec2-54-241-78-34.us-west-1.compute.amazonaws.com"
rep_server1 = "ec2-184-169-190-253.us-west-1.compute.amazonaws.com"
rep_server2 = "ec2-184-169-210-186.us-west-1.compute.amazonaws.com"
rep_server3 = "ec2-184-169-254-236.us-west-1.compute.amazonaws.com"

class TestSuite(unittest.TestCase):
  def setup(self):
    pass

  def test_basic(self):
    conn = HTTPConnection(singly_server, PORT)
    reset_server(conn)
    
    auction_duration = 3

    # Start an auction ends in 10 seconds
    current_time = int(time())
    end_time = current_time+3
    params = urlencode({'name':'foo', 'end_time':end_time})
    conn.request("POST", "/start_auction", params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual(data, 'None')

    # Get status without any bidders => "UNKNOWN"
    params = urlencode({'name':'foo'})
    conn.request("GET", "/status?" + params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual("UNKNOWN", data)

    # Client 1 bids 100
    params = urlencode({'name':'foo', 'client':1, 'bid':100})
    conn.request("POST", "/bid", params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual(data, 'None')

    # Client 2 bids 300
    params = urlencode({'name':'foo', 'client':2, 'bid':300})
    conn.request("POST", "/bid", params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual(data, 'None')

    # Client 1 bids 400
    params = urlencode({'name':'foo', 'client':1, 'bid':400})
    conn.request("POST", "/bid", params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual(data, 'None')

    # Client 3 bids 100
    params = urlencode({'name':'foo', 'client':3, 'bid':100})
    conn.request("POST", "/bid", params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual(data, 'None')

    # Get status again
    params = urlencode({'name':'foo'})
    conn.request("GET", "/status?" + params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual("1", data)

    # Get winner when auction's not over yet
    params = urlencode({'name':'foo'})
    conn.request("GET", "/winner?" + params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual("UNKNOWN", data)

    # Wait until auction's over
    sleep(auction_duration)

    # Get winner again
    params = urlencode({'name':'foo'})
    conn.request("GET", "/winner?" + params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual("1", data)

    # Start an auction with same name ends in 3 seconds
    current_time = int(time())
    end_time = current_time+3
    params = urlencode({'name':'foo', 'end_time':end_time})
    conn.request("POST", "/start_auction", params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual(data, 'None')

    # Get winner again
    params = urlencode({'name':'foo'})
    conn.request("GET", "/winner?" + params)
    response = conn.getresponse()
    data = response.read()
    self.assertEqual(response.status, 200)
    self.assertEqual("1", data)

def reset_server(conn):
  # reseting the server before each test
  conn.request("POST", "/rst")
  conn.getresponse().read()

if __name__ == "__main__":
  unittest.main()
