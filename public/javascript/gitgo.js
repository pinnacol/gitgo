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
    var attrs  = graph.attrs(canvas);
    var offset = graph.offset(list);
    
    context.strokeStyle = attrs.color;
    $(list).find('li').each(function(item) {
      var node = graph.node($(this), offset.top);
      
      // draw node
      context.fillRect(offset(node.x), node.top, attrs.radius, attrs.radius);
      
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
    
    // reposition the graph and data next to one another
    // note this assumes positioning on the items
    if (canvas.offset().top < list.offset().top) {
      list.css('top', offset.height);
    } else {
      canvas.css('top', offset.height);
    };
    
    list.css('left', offset.max());
  },
  
  attrs: function(canvas) {
    var attrs = {
      radius: 5,
      color: 'black'
    };
    return attrs;
  },
  
  // Returns a function to calculate and memoize the x offset for slots by slot
  // number. Additionally carries a 'top' attribute indicating the vertical
  // offset for all items in the list.
  offset: function(list) {
    var width = parseInt(list.attr('width') || 20);
    var memo = [];
    var max = 0;
    
    var offsetter = function(x) {
      var pos = memo[x];
      if (typeof pos !== 'number') {
        pos = x * width;
        memo[x] = pos;
        if (x > max) { max = x };
      }
      return pos;
    }
    
    offsetter.top = list.offset().top;
    offsetter.height = -1 * list.height() - 20;
    offsetter.max = function() { return memo[max]; };
    return offsetter;
  },
  
  // Returns an object containing attributes used to render a node for the
  // specified list item.
  node: function(item, offset) {
    var top    = item.offset().top - offset;
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