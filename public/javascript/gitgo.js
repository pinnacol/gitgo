var Gitgo = {};

Gitgo.Graph = {
  draw: function(doc) {
    var doc = $(doc).prepend('<canvas><p>Your browser doesn\'t support canvas.</p></canvas>');
    this.refresh(doc);
    return doc;
  },
  
  refresh: function(doc) {
    var list = doc.find(">ul");
    var canvas = doc.find(">canvas");
    var context = canvas.get(0).getContext('2d');
    
    var graph  = this;
    var attrs  = graph.attrs(canvas);
    var offset = graph.offset(doc, list, attrs);
    
    var nodes = []
    list.find('>li').each(function(item) {
      var node = graph.node($(this));
      
      node.x = offset(node.x);
      offset.each(node.current);
      offset.each(node.transitions);
      
      if (offset.width <= node.x) {
        offset.width = node.x + offset.x;
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
      context.fillRect(node.x - offset.x, node.top, attrs.radius * 2, attrs.radius * 2);
      
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
    
    // align css so proportions are correct
    canvas.css('margin-top', list.css('margin-top'));
    canvas.css('margin-bottom', list.css('margin-bottom'));
    canvas.css('padding-top', list.css('padding-top'));
    canvas.css('padding-bottom', list.css('padding-bottom'));
    
    list.css('top', -1 * canvas.outerHeight(true));
    list.css('left', canvas.outerWidth(true));
    list.css('width', doc.width() - canvas.outerWidth(true) - (list.outerWidth(true) - list.width()));
    
    doc.css('height', Math.max(canvas.outerHeight(true), list.outerHeight(true)));
  },
  
  attrs: function(canvas) {
    var attrs = {
      width: 10,
      radius: 3,
      color: 'black'
    };
    return attrs;
  },
  
  // Returns a function to calculate and memoize the x offset for slots by slot
  // number. Additionally carries a 'top' attribute indicating the vertical
  // offset for all items in the list.
  offset: function(doc, list, attrs) {
    var width = parseInt(list.attr('width') || attrs.width);
    var memo = [];
    
    var offset = function(x) {
      var pos = memo[x];
      if (typeof pos !== 'number') {
        pos = x * width + attrs.radius;
        memo[x] = pos;
      }
      return pos;
    };
    
    offset.each = function(array) {
      for (i = 0; i < array.length; i += 1) {
        array[i] = offset(array[i]);
      };
    };
    
    offset.height = list.height();
    offset.width  = 0;
    offset.x = attrs.radius;
    
    return offset;
  },
  
  // Returns an object containing attributes used to render a node for the
  // specified list item.
  node: function(item) {
    var top    = item.position().top;
    var height = item.outerHeight(true);
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