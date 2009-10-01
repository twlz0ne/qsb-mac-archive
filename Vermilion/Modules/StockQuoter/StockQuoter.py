#!/usr/bin/python
#
# Copyright 2009 Google Inc. All Rights Reserved.

"""A Google Quick Search plugin for stock quotes.

Given a user's Quick Search Box query, this search source
retrieves stock quotes for companies matching the query.

  StockQuoter: The core search source class.

The Google Finance feed can return some or all of the following
keys:

  avvo    * Average volume (float with multiplier, like '3.54M')
  beta    * Beta (float)
  c       * Amount of change while open (float)
  ccol    * (unknown) (chars)
  cl        Last perc. change
  cp      * Change perc. while open (float)
  e       * Exchange (text, like 'NASDAQ')
  ec      * After hours last change from close (float)
  eccol   * (unknown) (chars)
  ecp     * After hours last chage perc. from close (float)
  el      * After. hours last quote (float)
  el_cur  * (unknown) (float)
  elt       After hours last quote time (unknown)
  eo      * Exchange Open (0 or 1)
  eps     * Earnings per share (float)
  fwpe      Forward PE ratio (float)
  hi      * Price high (float)
  hi52    * 52 weeks high (float)
  id      * Company id (identifying number)
  l       * Last value while open (float)
  l_cur   * Last value at close (like 'l')
  lo      * Price low (float)
  lo52    * 52 weeks low (float)
  lt        Last value date/time
  ltt       Last trade time (Same as "lt" without the data)
  mc      * Market cap. (float with multiplier, like '123.45B')
  name    * Company name (text)
  op      * Open price (float)
  pe      * PE ratio (float)
  t       * Ticker (text)
  type    * Type (i.e. 'Company')
  vo      * Volume (float with multiplier, like '3.54M')

  * - Provided in the feed.
"""

__author__ = 'mrossetti@google.com (Mike Rossetti)'

import re
import sys
import thread
import time
import traceback
import urllib

try:
  import Vermilion
  import VermilionLocalize
except ImportError:

  class Vermilion(object):
    """Stub class used when running from the command line.

    Required when this script is run outside of the Quick Search Box.  This
    class is not needed when Vermilion is provided in native code by the
    Quick Search runtime.
    """
    IDENTIFIER = 'IDENTIFIER'
    DISPLAY_NAME = 'DISPLAY_NAME'
    SNIPPET = 'SNIPPET'
    IMAGE = 'IMAGE'
    TYPE = 'TYPE'

    class Query(object):
      """Stub for the query class used when running from the command line.

      Required when this script is run outside of the Quick Search Box.  This
      class is not needed when Query is provided in native code by the Quick
      Search runtime.
      """

      def __init__(self, phrase):
        """Stub the required data members."""
        self.raw_query = phrase
        self.normalized_query = object
        self.pivot_object = None
        self.finished = False
        self.results = []

      def SetResults(self, results):
        self.results = results

      def Finish(self):
        self.finished = True

  class VermilionLocalize(object):
    """Stub class used when running from the command line.

    Required when this script is run outside of the Quick Search Box.  This
    class is not needed when Vermilion is provided in native code by the
    Quick Search runtime.
    """

    def String(self, string):
      return string

QUOTE_URL = 'http://www.google.com/finance/info?infotype=infoquoteall&q=%s'
SOURCE_URL = 'http://www.google.com/finance?q=%s'
# <symbol> <price> (<change>/<change pct>%) <company name>
DISPLAY_NAME_FORMAT = '%s %s (%s/%s%%) %s'
SNIPPET_FORMAT = '%s Hi:%s/Lo:%s Vol:%s'  # <exchange> <hi>/<lo> Vol:<vol>
STOCK_QUOTE_TYPE = 'script.python.stockquote'

def XEncodeReplace(match_object):
  """Convert \\xnn encoded characters.
  
  Converts \\xnn encoded characters into their Unicode equivalent.
  
  Args:
    match: A string matched by an re pattern of '\\xnn'.
  
  Returns:
    A single character string containing the Unicode equivalent character
    (always within the ASCII range) if match is of the '\\xnn' pattern,
    otherwise the match string unchanged.
  """
  char_num_string = match_object.group(1)
  char_num = int(char_num_string, 16)
  replacement = chr(char_num)
  return replacement

class StockQuoter(object):
  """The stock quote search source.

  This class conforms to the search source protocol by
  providing the mandatory PerformSearch method and the optional
  IsValidSourceForQuery method.
  """

  def __init__(self):
    """Sets defaults for debugging and running from the command line.

    Modify the setting of debugging_is_enabled directly here if you
    want to see debugging information while running within another
    application, such as QSB under Mac OS X.
    """
    self.was_invoked_by_command_line = False
    self.debugging_is_enabled = False

  def _GetInvokedByCommandLine(self):
    """Returns True if we were invoked by command line."""
    return self.was_invoked_by_command_line

  def __GetInvokedByCommandLine(self):
    """Indirect accessor for 'invoked_by_command_line' property."""
    return self._GetInvokedByCommandLine()

  def _SetInvokedByCommandLine(self, invoked_by_command_line):
    """Sets if we were invoked via the command line for testing."""
    self.was_invoked_by_command_line = invoked_by_command_line

  def __SetInvokedByCommandLine(self, invoked_by_command_line):
    """Indirect setter for 'invoked_by_command_line' property."""
    self._SetInvokedByCommandLine(invoked_by_command_line)

  invoked_by_command_line = property(__GetInvokedByCommandLine,
                                     __SetInvokedByCommandLine,
                                     doc="""Gets or sets if we were invoked
                                            by command line.""")

  def _GetDebuggingEnabled(self):
    """Returns True if we want debugging output."""
    return self.debugging_is_enabled

  def __GetDebuggingEnabled(self):
    """Indirect accessor for 'debugging_enabled' property."""
    return self._GetDebuggingEnabled()

  def _SetDebuggingEnabled(self, debugging_enabled):
    """Sets if we were invoked via the command line for testing."""
    self.debugging_is_enabled = debugging_enabled

  def __SetDebuggingEnabled(self, debugging_enabled):
    """Indirect setter for 'debugging_enabled' property."""
    self._SetDebuggingEnabled(debugging_enabled)

  debugging_enabled = property(__GetDebuggingEnabled,
                               __SetDebuggingEnabled,
                               doc="""Gets or sets if we should output
                                      debugging information.""")

  def PerformSearch(self, query):
    """Kicks off a search for a stock quote.

    Args:
      query: A Vermilion.Query object containing the user's search query.
    """
    thread.start_new_thread(self.PerformSearchThread, (query,))

  def PerformSearchThread(self, query):
    """Searches for a stock quote.

    Args:
      query: A Vermilion.Query object containing the user's search query.

    Returns:
      An empty list or a list of one dictionaries representing the search
      results.  No list will be returned if the search term is not a valid
      stock symbol.
    """
    try:
      results = []
      terms = query.raw_query.split()
      if self.debugging_enabled:
        print "PerformSearch for query with terms: %s" % terms
      term = terms[0]
      # Perform a fetch from the finance server using the term as the
      # stock symbol.
      quote_url = QUOTE_URL % urllib.quote(term)
      if self.debugging_enabled:
        print "Requesting quote with URL: %s" % quote_url
      quote_connection = urllib.urlopen(quote_url)
      quote_raw_data = quote_connection.readlines()
      quote_connection.close()
      if self.debugging_enabled:
        print "Raw data returned from finance feed: %s" % quote_raw_data
      # The JSON from the finance feed may have \x26's in it, and perhaps
      # other improperly encoded characters.  Replace them with the
      # equivalent characters.  Precompile the pattern.
      pattern = re.compile('\\\\x(\d{2})')
      # It's JSON but this is a simple extraction.
      quote_dict = {}
      for line in quote_raw_data:
        line = line.rstrip('\n')
        line_parts = line.split(':')
        if len(line_parts) == 2:
          key, value = line_parts
          key = key.strip('" ,')
          # Perform the \xnn replacements here.
          value = pattern.sub(XEncodeReplace, value)
          value = value.strip('" ')
          if key and value:
            quote_dict[key] = value
      if self.debugging_enabled:
        print "Raw results dict: %s." % quote_dict
      # See if all of the required dictionary entries are available.
      required_keys = frozenset(['t', 'l', 'c', 'cp', 'name', 'e', 'hi',
                                 'lo', 'vo'])
      actual_keys = frozenset(quote_dict.keys())
      if required_keys <= actual_keys:
        result = self.CreateResult(quote_dict)
        if result is not None:
          results.append(result)
          if self.debugging_enabled:
            print "Results for '%s' were added: %s" % (term, result)
        elif self.debugging_enabled:
          print "Failed to create a result for '%s'." % term
      elif self.debugging_enabled:
        print "'%s' is not a valid stock symbol: " % term, quote_dict
      query.SetResults(results)
    except Exception, exception:
      # Catch everything to make sure that we never pass up the
      # call to query.Finish()
      if self.debugging_enabled:
        print "An exception was thrown. %s" % exception
        traceback.print_exc()
    query.Finish()

  def IsValidSourceForQuery(self, query):
    """Determines if the stock quote search source will handle the query.

    We reject any term that is comprosed of more than one word.

    Args:
      query: A Vermilion.Query object containing the user's search query

    Returns:
      True if this is a non-pivot query of three characters or more.
    """
    is_valid = False
    if query.pivot_object is None:
      terms = query.raw_query.split()
      if len(terms) == 1:
        is_valid = True
      elif self.debugging_enabled:
        print "'%s' has more than one word -- rejected." % terms
    if is_valid and self.debugging_enabled:
      print "'%s' is a valid, potential stock symbol." % terms
    return is_valid

  def CreateResult(self, quote_dict):
    """Composes a search result.

    Args:
      quote_dict: A dictionary containing the contents of the quote
      as provided by the Google Finance feed.

    Returns:
      A result dictionary containing values for the keys DISPLAY_NAME,
      IDENTIFIER, TYPE, IMAGE and SNIPPET keys.
    """
    result = {}
    symbol = quote_dict['t']
    source_url = SOURCE_URL % symbol
    if self.debugging_enabled:
      print "Source URL: %s." % source_url
    result[Vermilion.IDENTIFIER] = source_url
    #   <symbol> <price> <change> <change pct> <name>
    price = quote_dict['l']
    change = quote_dict['c']
    change_pct = quote_dict['cp']
    company_name = quote_dict['name']
    display_name = DISPLAY_NAME_FORMAT % (symbol, price, change, change_pct,
                                          company_name)
    if self.debugging_enabled:
      print "Display name: %s." % display_name
    result[Vermilion.DISPLAY_NAME] = display_name
    #   <exchange> <hi>/<lo> Vol:<vol>
    exchange_name = quote_dict['e']
    hi = quote_dict['hi']
    lo = quote_dict['lo']
    volume = quote_dict['vo']
    if self.invoked_by_command_line:
      snippet_format = SNIPPET_FORMAT
    else:
      snippet_format = VermilionLocalize.String(SNIPPET_FORMAT)
    snippet = snippet_format % (exchange_name, hi, lo, volume)
    if self.debugging_enabled:
      print "Snippet: %s." % snippet
    result[Vermilion.MAIN_ITEM] = symbol
    result[Vermilion.OTHER_ITEMS] = '%s %s' % (company_name, exchange_name)
    result[Vermilion.SNIPPET] = snippet
    result[Vermilion.TYPE] = STOCK_QUOTE_TYPE
    result[Vermilion.IMAGE] = 'StockQuoter.icns'
    return result


def main(argv=None):
  """Command line interface for easier testing."""
  if argv is None:
    argv = sys.argv[1:]

  if len(argv) < 1:
    print "Usage: StockQuoter <query>"
    return 1

  query = Vermilion.Query(argv[0])
  search = StockQuoter()
  search.invoked_by_command_line = True
  search.debugging_enabled = True
  if not search.IsValidSourceForQuery(query):
    print "Not a valid query"
    return 1
  search.PerformSearch(query)

  while query.finished is False:
    time.sleep(1)

  for result in query.results:
    print "Result: %s." % result

if __name__ == '__main__':
  sys.exit(main())
