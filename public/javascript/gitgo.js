var Gitgo = {};

Gitgo.Graph = {
  draw: function(canvas, data) {
    var context = $(canvas)[0].getContext('2d');
    var nodes = $(data).find('li');
    
    context.fillStyle = "rgb(0,0,0)";
    context.fillRect(30, 30, 50, 10 * nodes.length);
  },
  
  attrs: function (element) {
    var data = element.attr('graph').split(':', 4);
    var x = data[0];
    var y = data[1];
    var current = data[2];
    var transitions = data[3];
    
    var parseIntArray = function (string) {
      if (string.length == 0) { return []; };
      
      var i, ints = [], chars = string.split(',');
      for (i = 0; i < chars.length; i += 1) {
        ints[i] = parseInt(chars[i]);
      }
      
      return ints;
    };
    
    return [parseInt(x), parseInt(y), parseIntArray(current), parseIntArray(transitions)];
  }
};