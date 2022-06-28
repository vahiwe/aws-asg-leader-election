console.log('Loading ElectASGLeader');

var aws = require('aws-sdk');
var autoscaling = new aws.AutoScaling();
var ec2 = new aws.EC2();

var validStates  = [ 'Pending', 'Pending:Wait', 'Pending:Proceed', 'InService' ];
var leaderTagKey   = 'app:isLeader';
var leaderTagValue = 'true';

exports.handler = function(event, context) {
  console.log('Received event:');
  
  console.log( "eventbridge scaling event :" );
  
  console.log(event);

  let json = event.detail;

  //list all instances currently in the autoscaling group
  autoscaling.describeAutoScalingGroups( { 'AutoScalingGroupNames' : [json.AutoScalingGroupName] }, function(err, data) {
    if( err ) {
      console.log( 'Error loading autoscaling groups: ', err );
      context.fail();
      return;
    }
    
    console.log("autoscalingGroupName: ", json.AutoScalingGroupName);

    var asg = data.AutoScalingGroups.pop();
    var candidates = [];
    var allInstanceIds = [];

    asg.Instances.forEach( function( instance ) {
      allInstanceIds.push( instance.InstanceId );
      if( validStates.indexOf( instance.LifecycleState ) >= 0 ) {
        candidates.push( instance.InstanceId );
        console.log( 'Instance ' + instance.InstanceId + ' is a candidate for leader.' );
      }
    } );

    ec2.describeInstances( { 'InstanceIds' : candidates }, function(err, data) {
      if( err ) {
        console.log( 'Error loading autoscaling groups: ', err );
        context.fail();
        return;
      }

      var leaders = [];
      var newLeader = null;

      //find all leader instances
      data.Reservations.forEach( function( reservation ) {
        reservation.Instances.forEach( function( instance ) {
          instance.Tags.forEach( function( tag ) {
            if( tag.Key == leaderTagKey ) {
              leaders.push( instance );
            }
          });
        });
      });

      // Get leaders  instance ids
      var leaderInstanceIds = leaders.map(leader => leader.InstanceId);

      console.log("leader candidates: ", candidates);
      console.log("leaders: ", leaderInstanceIds);
    
      //if there's already a leader, don't change anything.
      if( leaders.length == 1 ) {
        console.log( 'Retaining leader instance ' + leaderInstanceIds[0] );
        context.succeed( leaders[0] );
        return;

        // if there is more than one leader, keep one of them.
      } else if( leaders.length > 1 ) {
        newLeader = leaderInstanceIds[0];

        // if there are no leaders and the triggering instance is coming online, make it the leader.
      } else if( json.Description.includes("Launching a new EC2 instance:")) {
        newLeader = json.EC2InstanceId;

        //Otherwise, just pick a leader.
      } else {
        newLeader = candidates[0];
      }

      //flip the tags on all instances.
      ec2.deleteTags( { 'Resources': allInstanceIds, 'Tags': [ { 'Key': leaderTagKey } ] }, function(err, data) {
        if( err ) {
          console.log( 'Error deleting tags from non-candidate instances: ', err );
          context.fail();
          return;
        }

        console.log( 'Cleared tags on ' + allInstanceIds.length + ' insances' );

        var params = {
          'Resources': [newLeader],
          'Tags': [ { 'Key': leaderTagKey, 'Value': leaderTagValue } ]
        };
        ec2.createTags( params, function() {
          if( err ) {
            console.log( 'Error creating leader tag on leader instance: ', err );
            context.fail();
            return;
          }

          console.log( 'Successfully tagged new leader instance', newLeader );
          context.succeed( newLeader );
        } )
      });


    });

  });
};
