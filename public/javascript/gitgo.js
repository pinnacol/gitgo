var Gitgo = {};

Gitgo.Graph = {
  draw: function(canvas, list) {
    var list = $(list);
    var canvas = $(canvas);
    var context = canvas.get(0).getContext('2d');
    
    // clear the context for rendering, and resize as necessary
    context.clearRect(0, 0, canvas.width(), canvas.height());
    canvas.attr('height', list.height());
    
    var graph  = this;
    var offset = graph.offset(list);
    
    $(list).find('li').each(function(item) {
      var node = graph.node($(this), offset.top);
      
      // draw node
      context.fillRect(offset(node.x), node.top, 3, 3);
      
      // draw verticals for current slots
      $.each(node.current, function(i, x) {
        context.beginPath();
        context.moveTo(offset(x), node.top);
        context.lineTo(offset(x), node.bottom);
        context.stroke();
      });
      
      // draw transitions
      $.each(node.transitions, function(i, target) {
        context.beginPath();
        context.moveTo(offset(node.x), node.top);
        context.lineTo(offset(node.x), node.middle);
        context.lineTo(offset(target), node.middle);
        context.lineTo(offset(target), node.bottom);
        context.stroke();
      });
    });
  },
  
  // Returns a function to calculate and memoize the x offset for slots by slot
  // number. Additionally carries a 'top' attribute indicating the vertical
  // offset for all items in the list.
  offset: function(list) {
    var width = parseInt(list.attr('width') || 20);
    var memo = [];
    
    var offsetter = function(x) {
      var pos = memo[x];
      if (typeof pos !== 'number') {
        pos = x * width;
        memo[x] = pos;
      }
      return pos;
    }
    
    offsetter.top = list.position().top;
    return offsetter;
  },
  
  // Returns an object containing attributes used to render a node for the
  // specified list item.
  node: function(item, offset) {
    var top    = item.position().top - offset;
    var height = item.outerHeight();
    var data   = item.attr('graph').split(':', 4);
    
    var parseIntArray = function (string) {
      if (string.length == 0) { return []; };
      
      var ints = [], chars = string.split(',');
      for (i = 0; i < chars.length; i += 1) {
        ints[i] = parseInt(chars[i]);
      }
      
      return ints;
    };
    
    var node = {
      id:     item.attr('id'),
      top:    top,
      middle: top + (height/2),
      bottom: top + height,
      x: parseInt(data[0]),
      y: parseInt(data[1]),
      current: parseIntArray(data[2]), 
      transitions: parseIntArray(data[3])
    };
    return node;
  }
};