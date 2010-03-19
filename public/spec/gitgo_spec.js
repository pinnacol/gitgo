describe 'Gitgo.Graph'
  describe '.attrs'
    it 'should return the graph attributes for the node'
      simple = $(fixture('simple'))
      Gitgo.Graph.attrs(simple.find('li:first')).should.eql [0, [0], null]
    end
    
    it 'should correctly parse branch and children indicies'
      simple = $(fixture('open_tails'))
      Gitgo.Graph.attrs(simple.find('#1')).should.eql [0, [0,1,2], [1,2]]
    end
  end
end