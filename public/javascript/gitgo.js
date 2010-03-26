var Gitgo = {};

Gitgo.Graph = {
  draw: function(canvas, list) {
    var list = $(list);
    var canvas = $(canvas);
    var context = canvas.get(0).getContext('2d');
    
    var graph  = this;
    var attrs  = graph.attrs(canvas);
    var offset = graph.offset(list, attrs);
    
    var nodes = []
    $(list).find('li').each(function(item) {
      var node = graph.node($(this));
      
      node.top    -= offset.top;
      node.middle -= offset.top;
      node.bottom -= offset.top;
      
      node.x = offset(node.x);
      offset.each(node.current);
      offset.each(node.transitions);
      
      if (offset.width < node.x) {
        offset.width = node.x;
      };
      
      nodes.push(node);
    });
    
    // clear the context for rendering, and resize as necessary
    context.clearRect(0, 0, canvas.width(), canvas.height());
    canvas.attr('height', offset.height);
    canvas.attr('width', offset.width);
    
    context.strokeStyle = attrs.color;
    $.each(nodes, function(i, node) {
      // draw node
      context.fillRect(node.x, node.top, attrs.radius, attrs.radius);
      
      // draw verticals for current slots
      $.each(node.current, function(j, x) {
        context.beginPath();
        context.moveTo(x, node.top);
        context.lineTo(x, node.bottom);
        context.stroke();
      });
      
      // draw transitions
      $.each(node.transitions, function(k, x) {
        context.beginPath();
        context.moveTo(node.x, node.top);
        context.lineTo(node.x, node.middle);
        context.lineTo(x, node.middle);
        context.lineTo(x, node.bottom);
        context.stroke();
      });
      
      // indent the item
      node.item.css('margin-left', node.x);
    });
  },
  
  attrs: function(canvas) {
    var attrs = {
      radius: 5,
      width: 10,
      color: 'black',
      padding_top: 20
    };
    return attrs;
  },
  
  // Returns a function to calculate and memoize the x offset for slots by slot
  // number. Additionally carries a 'top' attribute indicating the vertical
  // offset for all items in the list.
  offset: function(list, attrs) {
    var width = parseInt(list.attr('width') || attrs.width);
    var memo = [];
    
    var offset = function(x) {
      var pos = memo[x];
      if (typeof pos !== 'number') {
        pos = x * width;
        memo[x] = pos;
      }
      return pos;
    };
    
    offset.each = function(array) {
      for (i = 0; i < array.length; i += 1) {
        array[i] = offset(array[i]);
      };
    };
    
    offset.top    = list.offset().top - attrs.padding_top;
    offset.height = list.height();
    offset.width  = offset(0);
    
    return offset;
  },
  
  // Returns an object containing attributes used to render a node for the
  // specified list item.
  node: function(item) {
    var top    = item.offset().top;
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
      item:   item,
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