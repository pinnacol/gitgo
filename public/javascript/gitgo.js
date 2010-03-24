var Gitgo = {};

Gitgo.Graph = {
  draw: function(canvas, data) {
    var data = $(data);
    var canvas = $(canvas);
    var context = canvas.get(0).getContext('2d');
    
    // clear the context for rendering, and resize as necessary
    context.clearRect(0, 0, canvas.width(), canvas.height());
    
    var graph = this;
    var offset = graph.offset(data);
    $(data).find('li').each(function(node) {
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
  
  // Memoize function to calculate the x offset for slots by slot number.
  // Additionally carries a 'top' attribute indicating the offset for
  // all nodes within element.
  offset: function(element) {
    var width = parseInt(element.attr('width') || 20);
    var memo = [];
    
    var offsetter = function(x) {
      var pos = memo[x];
      if (typeof pos !== 'number') {
        pos = x * width;
        memo[x] = pos;
      }
      return pos;
    }
    
    offsetter.top = element.position().top;
    return offsetter;
  },
  
  node: function(element, offset) {
    var data = element.attr('graph').split(':', 4);
    var position = element.position();
    var height = element.outerHeight();
    
    var parseIntArray = function (string) {
      if (string.length == 0) { return []; };
      
      var ints = [], chars = string.split(',');
      for (i = 0; i < chars.length; i += 1) {
        ints[i] = parseInt(chars[i]);
      }
      
      return ints;
    };
    
    var node = {
      id: element.attr('id'),
      top: position.top - offset,
      middle: position.top + (height/2) - offset,
      bottom: position.top + height - offset,
      left: position.left,
      height: height,
      x: parseInt(data[0]),
      y: parseInt(data[1]),
      current: parseIntArray(data[2]), 
      transitions: parseIntArray(data[3])
    };
    return node;
  }
};