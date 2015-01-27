var React   = require('react');

var Spacer 	= require('react-redhat/Spacer');
var Label   = require('react-bootstrap/Label');

var Component = React.createClass({
    displayName: 'Case SBRs',
    getDefaultProps: function() {
	    return {
	    	// Determines whether to add a spacer preceding the labels or not
		    spacer: true
	    };
	},
    render: function() {
    	if (this.props.case == null 
    		|| this.props.case.resource.sbrs == null 
    		|| this.props.case.resource.sbrs.length == 0) {
    		return null;
    	}
                // {this.props.spacer == true ? <Spacer /> : null}
    	return (
    		<div>
                <div className='clearfix'></div>
	    		{this.props.case.resource.sbrs.map((s) => <span key={s}><Label bsStyle="default">{s}</Label>&nbsp;</span>)}
	    		&nbsp;
    		</div>
		)
    }
});

module.exports = Component;