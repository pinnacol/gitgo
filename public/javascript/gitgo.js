var Gitgo = {};

Gitgo.Graph = {
  attrs: function (element) {
    var result = [], data = element.attr('graph').split(',', 3);
    
    var convert = function (string) {
      switch(string.length) {
        case 0:
          return null;
        case 1:
          return [parseInt(string)];
        default: {
          var i, ints = [], chars = string.split('');
          for (i = 0; i < chars.length; i += 1) {
             ints[i] = parseInt(chars[i]);
          }
          return ints;
        }
      }
    };
    
    
    result[0] = parseInt(data[0]);
    result[1] = convert(data[1]);
    result[2] = convert(data[2]);
    
    return result
  }
};