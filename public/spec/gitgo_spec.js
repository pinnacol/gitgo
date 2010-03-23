describe 'Gitgo.Graph'
  describe '.attrs'
    it 'should return the graph attributes for the node'
      simple = $(fixture('fork'))
      Gitgo.Graph.attrs(simple.find('li:first')).should.eql [0, 1, [], [0, 1, 2]]
      Gitgo.Graph.attrs(simple.find('li:last')).should.eql [2, 4, [], []]
    end
  end
end