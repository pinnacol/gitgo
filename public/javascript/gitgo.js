var Gitgo = {};

Gitgo.Graph = {
  draw: function(canvas, data) {
    var data = $(data);
    var canvas = $(canvas);
    var context = canvas.get(0).getContext('2d');
    var graph = this;
    
    var slot_width = 20;
    context.clearRect(0, 0, canvas.width(), canvas.height());
    
    data.top = data.get(0).offsetTop;
    $(data).find('li').each(function(node) {
      var node = graph.node($(this));
      
      // draw node
      context.fillRect(node.x * slot_width, node.top - data.top, 3, 3);
      
      // draw verticals for current slots
      $.each(node.current, function(i, x) {
        context.beginPath();
        context.moveTo(x * slot_width, node.top - data.top);
        context.lineTo(x * slot_width, node.top - data.top + node.height);
        context.stroke();
      });
      
      // draw transitions
      $.each(node.transitions, function(i, x) {
        context.beginPath();
        context.moveTo(node.x * slot_width, node.top - data.top);
        context.lineTo(node.x * slot_width, node.top - data.top + (node.height / 2));
        context.lineTo(x * slot_width, node.top - data.top + (node.height / 2));
        context.lineTo(x * slot_width, node.top - data.top + node.height);
        context.stroke();
      });
    });
  },
  
  debug: function(canvas, debug) {
    var canvas = $(canvas);
    var context = $(canvas).get(0).getContext('2d');
    
    context.beginPath();
    context.lineTo(300, 0);
    context.lineTo(300, 150);
    context.lineTo(0, 150);
    context.lineTo(0, 0);
    context.closePath();
    context.stroke();
    
    $(debug).html(canvas.width() + ", " + canvas.height() + " (width, height)");
  },
  
  node: function(element) {
    var data = element.attr('graph').split(':', 4);
    var element = element.get(0);
    
    var parseIntArray = function (string) {
      if (string.length == 0) { return []; };
      
      var ints = [], chars = string.split(',');
      for (i = 0; i < chars.length; i += 1) {
        ints[i] = parseInt(chars[i]);
      }
      
      return ints;
    };
    
    var node = {
      id: element.getAttribute('id'),
      top: element.offsetTop,
      left: element.offsetLeft,
      width: element.offsetWidth,
      height: element.offsetHeight,
      x: parseInt(data[0]),
      y: parseInt(data[1]),
      current: parseIntArray(data[2]), 
      transitions: parseIntArray(data[3])
    };
    return node;
  }
};